//
//  EMAFilterTests.swift
//  GnomonTests
//

import XCTest
@testable import Gnomon

final class EMAFilterTests: XCTestCase {
    func testFirstSampleSeedsValue() {
        var filter = EMAFilter(alpha: 0.2)
        XCTAssertNil(filter.value)
        let first = filter.update(42.0)
        XCTAssertEqual(first, 42.0, "First sample should seed the value directly")
        XCTAssertEqual(filter.value, 42.0)
    }

    func testConvergesTowardInput() {
        var filter = EMAFilter(alpha: 0.2)
        filter.update(100)
        // Feeding 0s should asymptotically approach 0.
        var last = 100.0
        for _ in 0 ..< 20 {
            last = filter.update(0)
        }
        XCTAssertLessThan(last, 5.0, "After 20 zeros with α=0.2, value should be near 0")
    }

    func testAlphaOneMeansNoSmoothing() {
        var filter = EMAFilter(alpha: 1.0)
        filter.update(10)
        XCTAssertEqual(filter.update(50), 50, "α=1 just returns the input")
    }

    func testReset() {
        var filter = EMAFilter(alpha: 0.2)
        filter.update(100)
        filter.reset()
        XCTAssertNil(filter.value)
        XCTAssertEqual(filter.update(5), 5, "After reset, next sample seeds again")
    }

    func testExpectedAfterFiveSamples() {
        // Feeding 100 repeatedly: value should monotonically increase from 100.
        // Feeding 0 after seeded 100: y1 = 0.2*0 + 0.8*100 = 80, y2 = 64, y3 = 51.2, y4 = 40.96, y5 = 32.768
        var filter = EMAFilter(alpha: 0.2)
        filter.update(100)
        var y = 100.0
        for _ in 0 ..< 5 {
            y = filter.update(0)
        }
        XCTAssertEqual(y, 32.768, accuracy: 0.01)
    }

    func testSnapTriggersAfterSustainedLargeDelta() {
        var filter = EMAFilter(alpha: 0.2, snapThreshold: 50, snapDuration: 3)
        filter.update(500)
        // Three consecutive samples 450+ below previous → snap on the 3rd.
        XCTAssertEqual(filter.update(0), 400, accuracy: 0.01, "1st large delta: still EMA")
        XCTAssertFalse(filter.didSnapOnLastUpdate)
        XCTAssertEqual(filter.update(0), 320, accuracy: 0.01, "2nd large delta: still EMA")
        XCTAssertFalse(filter.didSnapOnLastUpdate)
        XCTAssertEqual(filter.update(0), 0, "3rd consecutive large delta: snap to sample")
        XCTAssertTrue(filter.didSnapOnLastUpdate, "Snap flag should fire on the jump")
        // Next stable sample must clear the flag so callers don't re-trigger.
        _ = filter.update(0)
        XCTAssertFalse(filter.didSnapOnLastUpdate)
    }

    func testSmallDeltaResetsSnapCounter() {
        // Verify a brief stable interval mid-transition prevents premature snap.
        var filter = EMAFilter(alpha: 0.2, snapThreshold: 50, snapDuration: 3)
        filter.update(500)
        _ = filter.update(0) // counter=1, value=400
        _ = filter.update(0) // counter=2, value=320
        _ = filter.update(310) // |310-320|=10 < 50 → counter reset, value≈318
        let y = filter.update(0) // counter=1, still EMA (not snapped to 0)
        XCTAssertGreaterThan(y, 200, "After counter reset, snap must not trigger")
        XCTAssertLessThan(y, 300, "Should have continued EMA decay, not snapped")
    }

    func testSnapDisabledByDefault() {
        // Default init keeps legacy behavior — no snap threshold.
        var filter = EMAFilter(alpha: 0.2)
        filter.update(500)
        for _ in 0 ..< 10 {
            _ = filter.update(0)
        }
        XCTAssertGreaterThan(filter.value ?? 0, 50, "Without snapThreshold, pure EMA decay")
    }

    func testResetClearsSnapCounter() {
        var filter = EMAFilter(alpha: 0.2, snapThreshold: 50, snapDuration: 3)
        filter.update(500)
        _ = filter.update(0)
        _ = filter.update(0) // counter=2
        filter.reset()
        filter.update(500)
        let y = filter.update(0) // counter should be 1, not 3
        XCTAssertGreaterThan(y, 300, "Reset must clear consecutive-delta counter")
    }
}
