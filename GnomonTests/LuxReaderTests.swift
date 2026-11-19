import Foundation

//
//  LuxReaderTests.swift
//  GnomonTests
//

import XCTest
@testable import Gnomon

final class LuxReaderTests: XCTestCase {
    func testFixedPointLuxIncludesDarkReadings() throws {
        XCTAssertEqual(try LuxReader.decodeLux(NSNumber(value: 0)), 0)
        XCTAssertEqual(try LuxReader.decodeLux(NSNumber(value: 32768)), 0.5)
        XCTAssertEqual(try LuxReader.decodeLux(NSNumber(value: 65536)), 1)
        XCTAssertEqual(try LuxReader.decodeLux(NSNumber(value: 5_886_541)), 89.82149, accuracy: 0.00001)
    }

    func testMissingAndMalformedReadingsThrow() {
        XCTAssertThrowsError(try LuxReader.decodeLux(nil))
        for malformed in [NSNumber(value: -1), NSNumber(value: true), NSNumber(value: 1.25)] {
            XCTAssertThrowsError(try LuxReader.decodeLux(malformed))
        }
        XCTAssertThrowsError(try LuxReader.decodeLux("50" as CFString))
    }
}

final class LuxReaderIntegrationTests: XCTestCase {
    private var shouldRun: Bool {
        ProcessInfo.processInfo.environment["GNOMON_INTEGRATION"] == "1"
    }

    func testCurrentLuxReturnsValidValue() async throws {
        try XCTSkipUnless(shouldRun, "Set GNOMON_INTEGRATION=1 to run hardware tests")
        let reader = LuxReader()
        let lux = try await reader.currentLux()
        XCTAssertGreaterThanOrEqual(lux, 0)
        XCTAssertLessThan(lux, 100_000, "Sanity bound: not in lava")
    }
}
