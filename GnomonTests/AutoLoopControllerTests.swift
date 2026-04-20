//
//  AutoLoopControllerTests.swift
//  GnomonTests
//

import XCTest
@testable import Gnomon

@MainActor
final class AutoLoopControllerTests: XCTestCase {
    func testUserSetBrightnessDisablesAuto() {
        let controller = AutoLoopController()
        XCTAssertTrue(controller.autoEnabled, "Default state should be Auto on")
        controller.userSetBrightness(50)
        XCTAssertFalse(controller.autoEnabled, "Manual slider interaction must disable Auto")
        XCTAssertEqual(controller.lastSentBrightness, 50)
        XCTAssertEqual(controller.targetBrightness, 50)
        XCTAssertNotNil(controller.manualOverrideAt)
    }

    func testToggleAutoFlipsFlag() {
        let controller = AutoLoopController()
        XCTAssertTrue(controller.autoEnabled)
        controller.toggleAuto()
        XCTAssertFalse(controller.autoEnabled)
        controller.toggleAuto()
        XCTAssertTrue(controller.autoEnabled)
    }

    func testResumeAutoClearsManualOverride() {
        let controller = AutoLoopController()
        controller.userSetBrightness(40)
        XCTAssertNotNil(controller.manualOverrideAt)
        controller.resumeAuto()
        XCTAssertTrue(controller.autoEnabled)
        XCTAssertNil(controller.manualOverrideAt)
    }

    func testUserSetBrightnessClampsOutOfRange() {
        let controller = AutoLoopController()
        controller.userSetBrightness(-10)
        XCTAssertEqual(controller.lastSentBrightness, 0)
        controller.userSetBrightness(150)
        XCTAssertEqual(controller.lastSentBrightness, 100)
    }

    func testTogglePause() {
        let controller = AutoLoopController()
        XCTAssertFalse(controller.isPaused)
        controller.togglePause()
        XCTAssertTrue(controller.isPaused)
        controller.togglePause()
        XCTAssertFalse(controller.isPaused)
    }
}
