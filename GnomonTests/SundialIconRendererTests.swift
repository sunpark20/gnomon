//
//  SundialIconRendererTests.swift
//  GnomonTests
//
//  Tests the internal rendering seam — shadow-angle math and image sizing.
//  No NSImage pixel comparison; the angle math is the deterministic surface.
//

import XCTest
@testable import Gnomon

final class SundialIconRendererTests: XCTestCase {
    func testMidnightPointsUp() {
        XCTAssertEqual(SundialIconRenderer.shadowAngle(hour: 0, minute: 0), 0, accuracy: 0.001)
    }

    func testSixAMPointsRight() {
        XCTAssertEqual(SundialIconRenderer.shadowAngle(hour: 6, minute: 0), 90, accuracy: 0.001)
    }

    func testNoonPointsDown() {
        XCTAssertEqual(SundialIconRenderer.shadowAngle(hour: 12, minute: 0), 180, accuracy: 0.001)
    }

    func testSixPMPointsLeft() {
        XCTAssertEqual(SundialIconRenderer.shadowAngle(hour: 18, minute: 0), 270, accuracy: 0.001)
    }

    func testTwentyFourWrapsToZero() {
        XCTAssertEqual(SundialIconRenderer.shadowAngle(hour: 24, minute: 0), 0, accuracy: 0.001)
    }

    func testMinutesInterpolate() {
        // 03:30 → 3.5h × 15°/h = 52.5°
        XCTAssertEqual(SundialIconRenderer.shadowAngle(hour: 3, minute: 30), 52.5, accuracy: 0.001)
    }

    func testImageMatchesStyleDiameter() {
        let image = SundialIconRenderer.image(hour: 9, minute: 15, style: .menuBarActive)
        XCTAssertEqual(image.size.width, 32, accuracy: 0.001)
        XCTAssertEqual(image.size.height, 32, accuracy: 0.001)
    }
}
