//
//  BrightnessCurveTests.swift
//  GnomonTests
//
//  Verifies the curve matches the sample table in PRD §5.2.1 v0.4.
//

import XCTest
@testable import Gnomon

final class BrightnessCurveTests: XCTestCase {
    /// Sample points from PRD §5.2.1 (corrected math):
    /// lux → b%
    ///   0  → 20
    ///   5  → 38  (originally mistyped as 24 in PRD v0.4; corrected in v0.5)
    ///  50  → 59
    /// 200  → 72
    /// 500  → 81
    /// 1000 → 88
    /// 2000 → 95
    func testPRDSamplePoints() {
        let cases: [(lux: Double, expected: Int)] = [
            (0, 20),
            (5, 38),
            (50, 59),
            (200, 72),
            (500, 81),
            (1000, 88),
            (2000, 95),
        ]
        for (lux, expected) in cases {
            let actual = BrightnessCurve.target(lux: lux)
            XCTAssertEqual(
                actual, expected, accuracy: 1,
                "lux=\(lux) expected ~\(expected) got \(actual)"
            )
        }
    }

    func testClampsAtBoundaries() {
        XCTAssertEqual(BrightnessCurve.target(lux: -100), 20, "Negative lux clamps to bMin")
        XCTAssertEqual(BrightnessCurve.target(lux: 5000), 95, "Way above ceiling clamps to bMax")
        XCTAssertEqual(BrightnessCurve.target(lux: 999_999), 95)
    }

    func testCustomParameters() {
        let params = BrightnessCurve.Parameters(minBrightness: 10, maxBrightness: 100, luxCeiling: 1000)
        XCTAssertEqual(BrightnessCurve.target(lux: 0, parameters: params), 10)
        XCTAssertEqual(BrightnessCurve.target(lux: 1000, parameters: params), 100)
    }

    func testMonotonicallyIncreasing() {
        var previous = BrightnessCurve.target(lux: 0)
        for lux in stride(from: 10, through: 2000, by: 50) {
            let current = BrightnessCurve.target(lux: Double(lux))
            XCTAssertGreaterThanOrEqual(
                current, previous,
                "Curve must be monotonically increasing; prev=\(previous) curr=\(current) at lux=\(lux)"
            )
            previous = current
        }
    }
}
