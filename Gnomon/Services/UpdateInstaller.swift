//
//  UpdateInstaller.swift
//  Gnomon
//
//  Downloads a release DMG, verifies the app inside it, swaps the running bundle
//  and relaunches. The swap happens in a detached shell that waits for this
//  process to exit, so the running binary is never overwritten in place.
//

import AppKit
import Foundation

public enum UpdateInstaller {
    public enum InstallError: LocalizedError {
        case downloadFailed
        case mountFailed(String)
        case appNotFoundInDMG
        case signatureRejected(String)
        case relaunchSetupFailed

        public var errorDescription: String? {
            switch self {
            case .downloadFailed: "The update could not be downloaded."
            case let .mountFailed(detail): "The update image could not be opened: \(detail)"
            case .appNotFoundInDMG: "No app was found inside the update image."
            case let .signatureRejected(detail): "The downloaded app failed verification: \(detail)"
            case .relaunchSetupFailed: "The update was downloaded but could not be installed."
            }
        }
    }

    /// Download the DMG, verify the bundled app's code signature, stage it, then
    /// hand off to a detached script that replaces this app and relaunches it.
    @MainActor
    public static func downloadAndInstall(dmgURL: URL) async throws {
        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GnomonUpdate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)

        let dmgPath = workDir.appendingPathComponent("update.dmg")
        let (downloaded, response) = try await URLSession.shared.download(from: dmgURL)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw InstallError.downloadFailed
        }
        try FileManager.default.moveItem(at: downloaded, to: dmgPath)

        let mountPoint = workDir.appendingPathComponent("mount")
        let stagedApp = try await stageApp(dmgPath: dmgPath, mountPoint: mountPoint, workDir: workDir)
        try await verifySignature(of: stagedApp)
        try swapAndRelaunch(stagedApp: stagedApp, workDir: workDir)
    }

    // MARK: - Steps

    private static func stageApp(dmgPath: URL, mountPoint: URL, workDir: URL) async throws -> URL {
        do {
            _ = try await ProcessRunner.run(
                "/usr/bin/hdiutil",
                args: ["attach", dmgPath.path, "-nobrowse", "-readonly", "-mountpoint", mountPoint.path]
            )
        } catch {
            throw InstallError.mountFailed(String(describing: error))
        }
        defer {
            Task.detached {
                _ = try? await ProcessRunner.run("/usr/bin/hdiutil", args: ["detach", mountPoint.path, "-force"])
            }
        }

        let contents = (try? FileManager.default.contentsOfDirectory(
            at: mountPoint,
            includingPropertiesForKeys: nil
        )) ?? []
        guard let appInDMG = contents.first(where: { $0.pathExtension == "app" }) else {
            throw InstallError.appNotFoundInDMG
        }
        let staged = workDir.appendingPathComponent(appInDMG.lastPathComponent)
        _ = try await ProcessRunner.run("/usr/bin/ditto", args: [appInDMG.path, staged.path])
        return staged
    }

    /// The downloaded app must pass strict codesign verification, and when the
    /// running app has a Team ID, the downloaded app must carry the same one.
    private static func verifySignature(of app: URL) async throws {
        do {
            _ = try await ProcessRunner.run(
                "/usr/bin/codesign",
                args: ["--verify", "--deep", "--strict", app.path]
            )
        } catch {
            throw InstallError.signatureRejected("codesign verify failed")
        }
        guard let runningTeam = try await teamIdentifier(of: Bundle.main.bundleURL) else { return }
        let downloadedTeam = try await teamIdentifier(of: app)
        guard downloadedTeam == runningTeam else {
            throw InstallError.signatureRejected("Team ID mismatch")
        }
    }

    private static func teamIdentifier(of app: URL) async throws -> String? {
        let output = try await ProcessRunner.run(
            "/bin/bash",
            args: ["-c", "codesign -dvv \"\(app.path)\" 2>&1 || true"]
        )
        for line in output.split(separator: "\n") where line.hasPrefix("TeamIdentifier=") {
            let value = String(line.dropFirst("TeamIdentifier=".count))
            return value == "not set" ? nil : value
        }
        return nil
    }

    @MainActor
    private static func swapAndRelaunch(stagedApp: URL, workDir: URL) throws {
        var destination = Bundle.main.bundleURL
        if destination.path.hasPrefix("/Volumes/") {
            destination = URL(fileURLWithPath: "/Applications").appendingPathComponent(
                destination.lastPathComponent
            )
        }

        let pid = ProcessInfo.processInfo.processIdentifier
        let script = """
        while /bin/kill -0 \(pid) 2>/dev/null; do /bin/sleep 0.3; done
        /bin/rm -rf "\(destination.path)"
        /usr/bin/ditto "\(stagedApp.path)" "\(destination.path)"
        /usr/bin/open "\(destination.path)"
        /bin/rm -rf "\(workDir.path)"
        """

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = ["-c", script]
        do {
            try task.run()
        } catch {
            throw InstallError.relaunchSetupFailed
        }
        NSApp.terminate(nil)
    }
}
