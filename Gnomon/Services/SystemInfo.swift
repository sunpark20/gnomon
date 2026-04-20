//
//  SystemInfo.swift
//  Gnomon
//
//  Collected once at startup and written to a header file next to the CSV.
//  Intended for bug reports: "here's a zip with my log.csv and system.txt".
//

import Foundation
import IOKit

public struct SystemInfo: Sendable {
    public let gnomonVersion: String
    public let macOSVersion: String
    public let machineModel: String
    public let chipArchitecture: String
    public let physicalMemoryGB: Int
    public let activeDisplays: [String]
    public let collectedAt: Date

    public static func collect(activeDisplays: [String] = []) -> SystemInfo {
        SystemInfo(
            gnomonVersion: appVersion(),
            macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            machineModel: hardwareModel(),
            chipArchitecture: cpuArchitecture(),
            physicalMemoryGB: Int(ProcessInfo.processInfo.physicalMemory / 1024 / 1024 / 1024),
            activeDisplays: activeDisplays,
            collectedAt: Date()
        )
    }

    /// Human-readable multi-line dump.
    public func rendered() -> String {
        let formatter = ISO8601DateFormatter()
        var lines: [String] = []
        lines.append("Gnomon diagnostics")
        lines.append("  collected: \(formatter.string(from: collectedAt))")
        lines.append("  gnomon: \(gnomonVersion)")
        lines.append("  macOS: \(macOSVersion)")
        lines.append("  machine: \(machineModel)")
        lines.append("  arch: \(chipArchitecture)")
        lines.append("  memory: \(physicalMemoryGB) GB")
        lines.append("  displays: \(activeDisplays.joined(separator: " | "))")
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Probes

    private static func appVersion() -> String {
        let bundle = Bundle.main
        let short = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(short) (\(build))"
    }

    private static func sysctlString(_ name: String) -> String {
        var size: size_t = 0
        sysctlbyname(name, nil, &size, nil, 0)
        guard size > 0 else { return "" }
        var buffer = [UInt8](repeating: 0, count: size)
        sysctlbyname(name, &buffer, &size, nil, 0)
        if let nullIndex = buffer.firstIndex(of: 0) {
            buffer = Array(buffer[..<nullIndex])
        }
        let decoded = String(bytes: buffer, encoding: .utf8) ?? ""
        return decoded.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func hardwareModel() -> String {
        let value = sysctlString("hw.model")
        return value.isEmpty ? "unknown" : value
    }

    private static func cpuArchitecture() -> String {
        let brand = sysctlString("machdep.cpu.brand_string")
        if !brand.isEmpty { return brand }
        let machine = sysctlString("hw.machine")
        return machine.isEmpty ? "unknown" : machine
    }
}
