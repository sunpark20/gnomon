//
//  UpdateChecker.swift
//  Gnomon
//
//  Checks GitHub Releases for a newer version and offers a three-way choice:
//  Update Now (download + install + relaunch), Skip This Version, Don't Ask Again.
//  Preferences: "updateCheckDisabled" (Bool), "updateSkippedVersion" (String).
//

import AppKit
import Foundation

@MainActor
public final class UpdateChecker: ObservableObject {
    public static let shared = UpdateChecker()

    public static let disabledKey = "updateCheckDisabled"
    public static let skippedVersionKey = "updateSkippedVersion"
    private static let latestReleaseURL =
        "https://api.github.com/repos/sunpark20/gnomon/releases/latest"

    public struct ReleaseInfo: Sendable {
        public let version: String
        public let dmgURL: URL
    }

    @Published public private(set) var statusMessage: String?
    @Published public private(set) var isBusy = false

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Public entry points

    /// Silent check at launch. Respects "Don't Ask Again" and skipped versions.
    public func checkOnLaunch() async {
        guard !defaults.bool(forKey: Self.disabledKey) else { return }
        guard let release = try? await fetchLatestRelease() else { return }
        guard Self.isVersion(release.version, newerThan: currentVersion) else { return }
        guard release.version != defaults.string(forKey: Self.skippedVersionKey) else { return }
        presentUpdateAlert(for: release)
    }

    /// Explicit check from Settings. Always reports a result and ignores skip state.
    public func checkManually() async {
        isBusy = true
        statusMessage = "Checking for updates…"
        defer { isBusy = false }
        do {
            let release = try await fetchLatestRelease()
            if Self.isVersion(release.version, newerThan: currentVersion) {
                statusMessage = nil
                presentUpdateAlert(for: release)
            } else {
                statusMessage = "You're up to date (v\(currentVersion))."
            }
        } catch {
            statusMessage = "Update check failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Version comparison

    /// Numeric segment-wise comparison, tolerant of a leading "v" ("1.10" > "1.9").
    public nonisolated static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        let lhs = numericSegments(of: candidate)
        let rhs = numericSegments(of: current)
        let count = max(lhs.count, rhs.count)
        for i in 0 ..< count {
            let l = i < lhs.count ? lhs[i] : 0
            let r = i < rhs.count ? rhs[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    private nonisolated static func numericSegments(of version: String) -> [Int] {
        var trimmed = version.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("v") || trimmed.hasPrefix("V") {
            trimmed = String(trimmed.dropFirst())
        }
        return trimmed.split(separator: ".").map { Int($0.prefix(while: \.isNumber)) ?? 0 }
    }

    // MARK: - Networking

    private var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    private enum CheckError: LocalizedError {
        case badResponse
        case noDMGAsset

        var errorDescription: String? {
            switch self {
            case .badResponse: "GitHub did not return a valid release."
            case .noDMGAsset: "The latest release has no DMG download."
            }
        }
    }

    private func fetchLatestRelease() async throws -> ReleaseInfo {
        guard let url = URL(string: Self.latestReleaseURL) else { throw CheckError.badResponse }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw CheckError.badResponse
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let release = try decoder.decode(LatestRelease.self, from: data)
        guard let dmg = release.assets.first(where: { $0.name.hasSuffix(".dmg") }) else {
            throw CheckError.noDMGAsset
        }
        var version = release.tagName
        if version.hasPrefix("v") { version = String(version.dropFirst()) }
        return ReleaseInfo(version: version, dmgURL: dmg.browserDownloadUrl)
    }

    // MARK: - Alert + actions

    private func presentUpdateAlert(for release: ReleaseInfo) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Gnomon \(release.version) is available"
        alert.informativeText =
            "You have v\(currentVersion). \"Update Now\" downloads and installs it, then relaunches."
        alert.addButton(withTitle: "Update Now")
        alert.addButton(withTitle: "Skip This Version")
        alert.addButton(withTitle: "Don't Ask Again")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            startInstall(of: release)
        case .alertSecondButtonReturn:
            defaults.set(release.version, forKey: Self.skippedVersionKey)
            statusMessage = "Skipped v\(release.version)."
        case .alertThirdButtonReturn:
            defaults.set(true, forKey: Self.disabledKey)
            statusMessage = "Automatic update checks are off."
        default:
            break
        }
    }

    private func startInstall(of release: ReleaseInfo) {
        isBusy = true
        statusMessage = "Downloading v\(release.version)…"
        Task { @MainActor in
            do {
                try await UpdateInstaller.downloadAndInstall(dmgURL: release.dmgURL)
                // On success the installer terminates and relaunches the app.
            } catch {
                isBusy = false
                statusMessage = nil
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = "Update failed"
                alert.informativeText = error.localizedDescription
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }
}

/// GitHub `releases/latest` payload (decoded with `.convertFromSnakeCase`).
private struct LatestRelease: Decodable {
    struct Asset: Decodable {
        let name: String
        let browserDownloadUrl: URL
    }

    let tagName: String
    let assets: [Asset]
}
