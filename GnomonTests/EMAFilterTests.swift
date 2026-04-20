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
}
