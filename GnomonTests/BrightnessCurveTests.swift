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

    func testDarkFloorReturnsMinBrightness() {
        // macOS returns ~1–3 lux with a fully covered sensor; without the floor
        // the curve outputs ~27–31 at those values, preventing the user's
        // configured min brightness from ever being reached.
        XCTAssertEqual(BrightnessCurve.target(lux: 0), 20)
        XCTAssertEqual(BrightnessCurve.target(lux: 1), 20, "1 lux below default 3-lux floor → b_min")
        XCTAssertEqual(BrightnessCurve.target(lux: 2), 20)
        XCTAssertEqual(BrightnessCurve.target(lux: 3), 20, "3 lux at floor boundary → b_min")
        XCTAssertGreaterThan(BrightnessCurve.target(lux: 4), 20, "Just above floor → curve takes over")
    }

    func testCustomDarkFloor() {
        let params = BrightnessCurve.Parameters(
            minBrightness: 10, maxBrightness: 100, luxCeiling: 1000, darkFloorLux: 0
        )
        // Floor=0 means only negative lux hits the floor; tiny positive values use the curve.
        XCTAssertEqual(BrightnessCurve.target(lux: 0, parameters: params), 10)
        XCTAssertGreaterThan(BrightnessCurve.target(lux: 0.5, parameters: params), 10)
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
