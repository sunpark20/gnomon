//
//  M1DDCClient.swift
//  Gnomon
//
//  Swift wrapper around the `m1ddc` CLI.
//  Reference: https://github.com/waydabber/m1ddc
//

import Foundation

public struct M1DDCClient: Sendable {
    public enum ClientError: Error, LocalizedError {
        case displayNotFound(slot: Int)
        case parseFailure(String)

        public var errorDescription: String? {
            switch self {
            case let .displayNotFound(slot):
                "Display at slot \(slot) not found"
            case let .parseFailure(line):
                "Could not parse m1ddc output: \(line)"
            }
        }
    }

    /// Default Homebrew install path on Apple Silicon.
    public static let defaultPath = "/opt/homebrew/bin/m1ddc"

    public let executablePath: String

    public init(executablePath: String = M1DDCClient.defaultPath) {
        self.executablePath = executablePath
    }

    // MARK: - Discovery

    /// Returns all DDC-addressable displays in the order m1ddc reports them.
    ///
    /// Sample m1ddc output line: `[1] LG HDR 4K (57E749D2-BBF2-4931-8EBC-6B9A3D4FF8A2)`
    public func listDisplays() async throws -> [MonitorID] {
        let stdout = try await ProcessRunner.run(executablePath, args: ["display", "list"])
        return Self.parseDisplayList(stdout)
    }

    static func parseDisplayList(_ text: String) -> [MonitorID] {
        var monitors: [MonitorID] = []
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Expected shape: "[1] LG HDR 4K (UUID)"
            guard trimmed.hasPrefix("[") else { continue }
            guard let closeSlot = trimmed.firstIndex(of: "]") else { continue }
            let slotString = trimmed[trimmed.index(after: trimmed.startIndex) ..< closeSlot]
            guard let slot = Int(slotString) else { continue }

            let rest = trimmed[trimmed.index(after: closeSlot)...].trimmingCharacters(in: .whitespaces)
            guard let openParen = rest.lastIndex(of: "("),
                  let closeParen = rest.lastIndex(of: ")"),
                  openParen < closeParen else
            {
                monitors.append(MonitorID(slot: slot, displayName: rest, uuid: ""))
                continue
            }

            let name = rest[..<openParen].trimmingCharacters(in: .whitespaces)
            let uuid = String(rest[rest.index(after: openParen) ..< closeParen])
            monitors.append(MonitorID(slot: slot, displayName: name, uuid: uuid))
        }
        return monitors
    }

    // MARK: - Brightness

    public func getBrightness(on monitor: MonitorID) async throws -> Int {
        try await getInt(property: "luminance", on: monitor)
    }

    public func setBrightness(_ value: Int, on monitor: MonitorID) async throws {
        try await setInt(property: "luminance", value: value, on: monitor)
    }

    // MARK: - Contrast

    public func getContrast(on monitor: MonitorID) async throws -> Int {
        try await getInt(property: "contrast", on: monitor)
    }

    public func setContrast(_ value: Int, on monitor: MonitorID) async throws {
        try await setInt(property: "contrast", value: value, on: monitor)
    }

    // MARK: - Internals

    private func getInt(property: String, on monitor: MonitorID) async throws -> Int {
        let stdout = try await ProcessRunner.run(
            executablePath,
            args: ["display", String(monitor.slot), "get", property]
        )
        let trimmed = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Int(trimmed) else {
            throw ClientError.parseFailure(trimmed)
        }
        return value
    }

    private func setInt(property: String, value: Int, on monitor: MonitorID) async throws {
        let clamped = min(max(value, 0), 100)
        _ = try await ProcessRunner.run(
            executablePath,
            args: ["display", String(monitor.slot), "set", property, String(clamped)]
        )
    }
}
