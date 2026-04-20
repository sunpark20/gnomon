//
//  CSVLoggerTests.swift
//  GnomonTests
//

import XCTest
@testable import Gnomon

final class CSVLoggerTests: XCTestCase {
    private func makeTempLogger(retention: TimeInterval = 30 * 24 * 60 * 60) -> (CSVLogger, URL) {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            "gnomon-tests-\(UUID().uuidString)",
            isDirectory: true
        )
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let url = tempDir.appendingPathComponent("log.csv")
        return (CSVLogger(fileURL: url, retentionInterval: retention), url)
    }

    func testEnsureFileCreatesHeader() async throws {
        let (logger, url) = makeTempLogger()
        try await logger.ensureFile()
        let contents = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(contents.hasPrefix(CSVLogger.header))
    }

    func testAppendAddsRow() async throws {
        let (logger, url) = makeTempLogger()
        let entry = CSVLogEntry(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            rawLux: 428.5,
            emaLux: 420.0,
            targetBrightness: 81,
            sentBrightness: 81,
            contrast: 70,
            autoOn: true,
            manualOverride: false,
            bMin: 20,
            bMax: 95
        )
        try await logger.append(entry)
        let contents = try String(contentsOf: url, encoding: .utf8)
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: true)
        XCTAssertEqual(lines.count, 2, "Header + 1 row")
        XCTAssertTrue(contents.contains("428.50"))
        XCTAssertTrue(contents.contains("81"))
        XCTAssertTrue(contents.hasSuffix("20,95\n"), "Row must end with bMin,bMax")
    }

    func testHeaderIncludesBrightnessBounds() {
        XCTAssertTrue(CSVLogger.header.hasSuffix(",b_min,b_max"))
    }

    func testEnsureFileBacksUpOutdatedSchema() async throws {
        let (logger, url) = makeTempLogger()
        // Write a file with an old 8-column header.
        let oldHeader = "timestamp,raw_lux,ema_lux,target_brightness,sent_brightness,contrast,auto_on,manual_override"
        try (oldHeader + "\n2026-01-01T00:00:00Z,0,0,0,0,70,1,0\n")
            .write(to: url, atomically: true, encoding: .utf8)

        try await logger.ensureFile()

        let newHeader = try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n", maxSplits: 1)
            .first.map(String.init) ?? ""
        XCTAssertEqual(newHeader, CSVLogger.header, "Outdated file should be replaced with current header")

        let backup = url.appendingPathExtension("v1")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: backup.path),
            "Old file should be preserved as .v1"
        )
    }

    func testRotateDropsOldRows() async throws {
        let (logger, url) = makeTempLogger(retention: 3600) // 1 hour retention
        let now = Date()
        let old = CSVLogEntry(
            timestamp: now.addingTimeInterval(-7200), // 2 hours ago
            rawLux: 10, emaLux: 10,
            targetBrightness: 30, sentBrightness: 30,
            contrast: 70, autoOn: true, manualOverride: false,
            bMin: 20, bMax: 95
        )
        let fresh = CSVLogEntry(
            timestamp: now.addingTimeInterval(-60),
            rawLux: 400, emaLux: 400,
            targetBrightness: 75, sentBrightness: 75,
            contrast: 70, autoOn: true, manualOverride: false,
            bMin: 20, bMax: 95
        )
        try await logger.append(old)
        try await logger.append(fresh)

        try await logger.rotate(now: now)
        let contents = try String(contentsOf: url, encoding: .utf8)
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: true)
        XCTAssertEqual(lines.count, 2, "Header + only the fresh row should remain")
        XCTAssertFalse(contents.contains("10.00,10.00"))
        XCTAssertTrue(contents.contains("400.00"))
    }
}
