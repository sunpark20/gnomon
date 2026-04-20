//
//  CSVLogger.swift
//  Gnomon
//
//  Appends DDC-sync and manual-override events to a CSV file for later
//  analysis. 30-day retention (old rows purged on startup).
//  PRD §5.10.
//

import Foundation

public struct CSVLogEntry: Sendable {
    public let timestamp: Date
    public let rawLux: Double
    public let emaLux: Double
    public let targetBrightness: Int
    public let sentBrightness: Int
    public let contrast: Int
    public let autoOn: Bool
    public let manualOverride: Bool
    public let bMin: Int
    public let bMax: Int

    public init(
        timestamp: Date = Date(),
        rawLux: Double,
        emaLux: Double,
        targetBrightness: Int,
        sentBrightness: Int,
        contrast: Int,
        autoOn: Bool,
        manualOverride: Bool,
        bMin: Int,
        bMax: Int
    ) {
        self.timestamp = timestamp
        self.rawLux = rawLux
        self.emaLux = emaLux
        self.targetBrightness = targetBrightness
        self.sentBrightness = sentBrightness
        self.contrast = contrast
        self.autoOn = autoOn
        self.manualOverride = manualOverride
        self.bMin = bMin
        self.bMax = bMax
    }

    public func csvLine() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return [
            formatter.string(from: timestamp),
            String(format: "%.2f", rawLux),
            String(format: "%.2f", emaLux),
            String(targetBrightness),
            String(sentBrightness),
            String(contrast),
            autoOn ? "1" : "0",
            manualOverride ? "1" : "0",
            String(bMin),
            String(bMax),
        ].joined(separator: ",")
    }
}

public actor CSVLogger {
    public static let header =
        "timestamp,raw_lux,ema_lux,target_brightness,sent_brightness,contrast,auto_on,manual_override,b_min,b_max"
    private let fileURL: URL
    private let fileManager: FileManager
    private let retentionInterval: TimeInterval

    public init(
        fileURL: URL = CSVLogger.defaultLogURL(),
        fileManager: FileManager = .default,
        retentionInterval: TimeInterval = 30 * 24 * 60 * 60
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        self.retentionInterval = retentionInterval
    }

    public var url: URL {
        fileURL
    }

    public static func defaultLogURL() -> URL {
        defaultLogDirectory().appendingPathComponent("log.csv", isDirectory: false)
    }

    public static func defaultLogDirectory() -> URL {
        let base = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = base?.appendingPathComponent("Gnomon", isDirectory: true)
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("Gnomon", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Writes a diagnostics header file (system.txt) that sits next to the
    /// CSV. Called once per launch.
    public func writeDiagnostics(_ info: SystemInfo) async throws {
        let dir = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("system.txt")
        try info.rendered().write(to: url, atomically: true, encoding: .utf8)
    }

    /// Ensures the log file exists with the current header row. If the existing
    /// file was written with an older schema, it is renamed to `log.csv.v<n>`
    /// and a fresh file with the current header is started. Old versions are
    /// preserved so historical data isn't lost on schema upgrades.
    public func ensureFile() throws {
        let dir = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: fileURL.path) {
            if let existingHeader = try? readFirstLine(of: fileURL),
               existingHeader != CSVLogger.header
            {
                let backupURL = nextBackupURL(for: fileURL)
                try? fileManager.moveItem(at: fileURL, to: backupURL)
            } else {
                return
            }
        }
        let payload = CSVLogger.header + "\n"
        try payload.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private func readFirstLine(of url: URL) throws -> String {
        let contents = try String(contentsOf: url, encoding: .utf8)
        return contents.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? ""
    }

    private func nextBackupURL(for url: URL) -> URL {
        let dir = url.deletingLastPathComponent()
        let base = url.lastPathComponent
        var index = 1
        while true {
            let candidate = dir.appendingPathComponent("\(base).v\(index)")
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            index += 1
        }
    }

    public func append(_ entry: CSVLogEntry) async throws {
        try ensureFile()
        let line = entry.csvLine() + "\n"
        guard let data = line.data(using: .utf8) else { return }
        let handle = try FileHandle(forWritingTo: fileURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        try handle.close()
    }

    /// Removes rows older than retentionInterval. Runs on startup (not every write).
    public func rotate(now: Date = Date()) async throws {
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        var lines = contents.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        guard !lines.isEmpty else { return }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let cutoff = now.addingTimeInterval(-retentionInterval)

        let header = lines[0]
        let rows = Array(lines.dropFirst())
        let kept = rows.filter { row in
            let first = row.split(separator: ",", maxSplits: 1).first.map(String.init) ?? ""
            guard let date = formatter.date(from: first) else { return true } // keep unparseable
            return date >= cutoff
        }
        lines = [header] + kept
        let payload = lines.joined(separator: "\n") + "\n"
        try payload.write(to: fileURL, atomically: true, encoding: .utf8)
    }
}
