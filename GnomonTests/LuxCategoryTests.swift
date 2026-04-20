//
//  LuxCategoryTests.swift
//  GnomonTests
//

import XCTest
@testable import Gnomon

final class LuxCategoryTests: XCTestCase {
    func testBoundaryValues() {
        XCTAssertEqual(LuxCategory.classify(0), .pitchDark)
        XCTAssertEqual(LuxCategory.classify(9.99), .pitchDark)
        XCTAssertEqual(LuxCategory.classify(10), .veryDim)
        XCTAssertEqual(LuxCategory.classify(49.99), .veryDim)
        XCTAssertEqual(LuxCategory.classify(50), .dimIndoor)
        XCTAssertEqual(LuxCategory.classify(199.99), .dimIndoor)
        XCTAssertEqual(LuxCategory.classify(200), .office)
        XCTAssertEqual(LuxCategory.classify(499.99), .office)
        XCTAssertEqual(LuxCategory.classify(500), .bright)
        XCTAssertEqual(LuxCategory.classify(999.99), .bright)
        XCTAssertEqual(LuxCategory.classify(1000), .softDaylight)
        XCTAssertEqual(LuxCategory.classify(1999.99), .softDaylight)
        XCTAssertEqual(LuxCategory.classify(2000), .directSunlight)
        XCTAssertEqual(LuxCategory.classify(50000), .directSunlight)
    }

    func testNegativeValueClampsToDarkest() {
        XCTAssertEqual(LuxCategory.classify(-5), .pitchDark)
    }

    func testAllCategoriesHavePhrases() {
        for category in LuxCategory.allCases {
            let pool = WittyLabels.phrases[category]
            XCTAssertNotNil(pool, "Missing phrases for \(category)")
            XCTAssertGreaterThanOrEqual(pool?.count ?? 0, 3, "\(category) should have >= 3 phrases")
        }
    }

    func testPickReturnsStablePhrase() {
        let first = WittyLabels.pick(for: .office, seed: 42)
        let second = WittyLabels.pick(for: .office, seed: 42)
        XCTAssertEqual(first, second, "Same seed should give same phrase")
    }
}
