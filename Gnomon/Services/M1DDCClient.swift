//
//  M1DDCClient.swift
//  Gnomon
//
//  DDC client using native IOAVService (Apple Silicon).
//  No external binary dependency — replaces the old m1ddc shell-out.
//

import Foundation

public struct M1DDCClient: Sendable {
    public enum ClientError: Error, LocalizedError {
        case displayNotFound(slot: Int)
        case ddcReadFailed
        case ddcWriteFailed

        public var errorDescription: String? {
            switch self {
            case let .displayNotFound(slot):
                "Display at slot \(slot) not found"
            case .ddcReadFailed:
                "DDC read failed — check monitor connection"
            case .ddcWriteFailed:
                "DDC write failed — check monitor connection"
            }
        }
    }

    public init() {}

    // MARK: - Discovery

    public func listDisplays() async throws -> [MonitorID] {
        let displays = await Task.detached {
            NativeDDC.discoverDisplays()
        }.value

        return displays.enumerated().map { index, display in
            MonitorID(
                slot: index + 1,
                displayName: display.name,
                uuid: String(display.entryID)
            )
        }
    }

    // MARK: - Brightness

    public func getBrightness(on monitor: MonitorID) async throws -> Int {
        let entryID = try entryID(for: monitor)
        return try await Task.detached {
            guard let value = NativeDDC.readVCP(.brightness, entryID: entryID) else {
                throw ClientError.ddcReadFailed
            }
            return value
        }.value
    }

    public func setBrightness(_ value: Int, on monitor: MonitorID) async throws {
        let entryID = try entryID(for: monitor)
        let clamped = min(max(value, 0), 100)
        try await Task.detached {
            guard NativeDDC.writeVCP(.brightness, value: clamped, entryID: entryID) else {
                throw ClientError.ddcWriteFailed
            }
        }.value
    }

    // MARK: - Contrast

    public func getContrast(on monitor: MonitorID) async throws -> Int {
        let entryID = try entryID(for: monitor)
        return try await Task.detached {
            guard let value = NativeDDC.readVCP(.contrast, entryID: entryID) else {
                throw ClientError.ddcReadFailed
            }
            return value
        }.value
    }

    public func setContrast(_ value: Int, on monitor: MonitorID) async throws {
        let entryID = try entryID(for: monitor)
        let clamped = min(max(value, 0), 100)
        try await Task.detached {
            guard NativeDDC.writeVCP(.contrast, value: clamped, entryID: entryID) else {
                throw ClientError.ddcWriteFailed
            }
        }.value
    }

    // MARK: - Internals

    private func entryID(for monitor: MonitorID) throws -> UInt64 {
        guard let id = UInt64(monitor.uuid) else {
            throw ClientError.displayNotFound(slot: monitor.slot)
        }
        return id
    }

    // MARK: - Legacy CLI parser (kept for test backward compatibility)

    static func parseDisplayList(_ text: String) -> [MonitorID] {
        var monitors: [MonitorID] = []
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
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
}
