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
            manualOverride: false
        )
        try await logger.append(entry)
        let contents = try String(contentsOf: url, encoding: .utf8)
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: true)
        XCTAssertEqual(lines.count, 2, "Header + 1 row")
        XCTAssertTrue(contents.contains("428.50"))
        XCTAssertTrue(contents.contains("81"))
    }

    func testRotateDropsOldRows() async throws {
        let (logger, url) = makeTempLogger(retention: 3600) // 1 hour retention
        let now = Date()
        let old = CSVLogEntry(
            timestamp: now.addingTimeInterval(-7200), // 2 hours ago
            rawLux: 10, emaLux: 10,
            targetBrightness: 30, sentBrightness: 30,
            contrast: 70, autoOn: true, manualOverride: false
        )
        let fresh = CSVLogEntry(
            timestamp: now.addingTimeInterval(-60),
            rawLux: 400, emaLux: 400,
            targetBrightness: 75, sentBrightness: 75,
            contrast: 70, autoOn: true, manualOverride: false
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
