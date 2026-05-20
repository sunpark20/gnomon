//
//  AutoLoopDependencies.swift
//  Gnomon
//
//  Thin dependency wrapper for AutoLoopController tests.
//

import Foundation

struct AutoLoopDependencies {
    let currentLux: @Sendable () async throws -> Double
    let listDisplays: @Sendable () async throws -> [MonitorID]
    let getBrightness: @Sendable (MonitorID) async throws -> Int
    let setBrightness: @Sendable (Int, MonitorID) async throws -> Void
    let getContrast: @Sendable (MonitorID) async throws -> Int
    let setContrast: @Sendable (Int, MonitorID) async throws -> Void
    let ensureLogFile: @Sendable () async throws -> Void
    let rotateLog: @Sendable () async throws -> Void
    let writeDiagnostics: @Sendable (SystemInfo) async throws -> Void
    let appendLog: @Sendable (CSVLogEntry) async throws -> Void

    static func live(
        luxReader: LuxReader,
        ddcClient: M1DDCClient,
        logger: CSVLogger
    ) -> AutoLoopDependencies {
        AutoLoopDependencies(
            currentLux: {
                try await luxReader.currentLux()
            },
            listDisplays: {
                try await ddcClient.listDisplays()
            },
            getBrightness: { monitor in
                try await ddcClient.getBrightness(on: monitor)
            },
            setBrightness: { value, monitor in
                try await ddcClient.setBrightness(value, on: monitor)
            },
            getContrast: { monitor in
                try await ddcClient.getContrast(on: monitor)
            },
            setContrast: { value, monitor in
                try await ddcClient.setContrast(value, on: monitor)
            },
            ensureLogFile: {
                try await logger.ensureFile()
            },
            rotateLog: {
                try await logger.rotate()
            },
            writeDiagnostics: { info in
                try await logger.writeDiagnostics(info)
            },
            appendLog: { entry in
                try await logger.append(entry)
            }
        )
    }
}
