//
//  BrightnessCurveTests.swift
//  GnomonTests
//
//  Verifies the curve matches the sample table in PRD §5.2.1 v0.4.
//

import XCTest
@testable import Gnomon

final class BrightnessCurveTests: XCTestCase {
    /// Sample points from PRD §5.2.1 using PRD-recommended parameters.
    func testPRDSamplePoints() {
        let prd = BrightnessCurve.Parameters(
            minBrightness: 20, maxBrightness: 95, luxCeiling: 2000, darkFloorLux: 3
        )
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
            let actual = BrightnessCurve.target(lux: lux, parameters: prd)
            XCTAssertEqual(
                actual, expected, accuracy: 1,
                "lux=\(lux) expected ~\(expected) got \(actual)"
            )
        }
    }

    func testClampsAtBoundaries() {
        XCTAssertEqual(BrightnessCurve.target(lux: -100), 0, "Negative lux clamps to bMin")
        XCTAssertEqual(BrightnessCurve.target(lux: 5000), 100, "Way above ceiling clamps to bMax")
        XCTAssertEqual(BrightnessCurve.target(lux: 999_999), 100)
    }

    func testCustomParameters() {
        let params = BrightnessCurve.Parameters(minBrightness: 10, maxBrightness: 100, luxCeiling: 1000)
        XCTAssertEqual(BrightnessCurve.target(lux: 0, parameters: params), 10)
        XCTAssertEqual(BrightnessCurve.target(lux: 1000, parameters: params), 100)
    }

    func testDarkFloorReturnsMinBrightness() {
        XCTAssertEqual(BrightnessCurve.target(lux: 0), 0)
        XCTAssertEqual(BrightnessCurve.target(lux: 5), 0, "5 lux below default 15-lux floor → b_min")
        XCTAssertEqual(BrightnessCurve.target(lux: 15), 0, "15 lux at floor boundary → b_min")
        XCTAssertGreaterThan(BrightnessCurve.target(lux: 16), 0, "Just above floor → curve takes over")
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
