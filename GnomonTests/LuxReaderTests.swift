//
//  LuxReaderTests.swift
//  GnomonTests
//

import XCTest
@testable import Gnomon

final class LuxReaderParseTests: XCTestCase {
    func testParseObjCStyleOutput() throws {
        let sample = """
                   AlphaGamma = 1;
                   AggregatedLux = "109.1691";
                   CBAutoBrightnessAvailable = 1;
        """
        let value = try LuxReader.extractAggregatedLux(from: sample)
        XCTAssertEqual(value, 109.1691, accuracy: 0.0001)
    }

    func testParseObjCStyleWithoutQuotes() throws {
        let sample = "AggregatedLux = 428.5;"
        let value = try LuxReader.extractAggregatedLux(from: sample)
        XCTAssertEqual(value, 428.5, accuracy: 0.001)
    }

    func testParseXMLPlistStyle() throws {
        let sample = """
        <dict>
            <key>AggregatedLux</key>
            <real>616.75</real>
            <key>OtherKey</key>
            <integer>1</integer>
        </dict>
        """
        let value = try LuxReader.extractAggregatedLux(from: sample)
        XCTAssertEqual(value, 616.75, accuracy: 0.01)
    }

    func testParseMissingKeyThrows() {
        XCTAssertThrowsError(try LuxReader.extractAggregatedLux(from: "nothing relevant here"))
    }

    func testParseZeroValue() throws {
        let sample = "AggregatedLux = 0;"
        let value = try LuxReader.extractAggregatedLux(from: sample)
        XCTAssertEqual(value, 0)
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
