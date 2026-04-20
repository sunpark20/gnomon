//
//  HotkeyManagerTests.swift
//  GnomonTests
//

import AppKit
import Carbon.HIToolbox
import XCTest
@testable import Gnomon

@MainActor
final class HotkeyManagerTests: XCTestCase {
    private func makeEvent(keyCode: Int, modifiers: NSEvent.ModifierFlags) -> NSEvent? {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: UInt16(keyCode)
        )
    }

    private let required: NSEvent.ModifierFlags = [.control, .option, .command]

    func testBrightnessUpMapping() throws {
        let event = try XCTUnwrap(makeEvent(keyCode: kVK_UpArrow, modifiers: required))
        XCTAssertEqual(HotkeyManager.mapAction(from: event), .brightnessUp)
    }

    func testBrightnessDownMapping() throws {
        let event = try XCTUnwrap(makeEvent(keyCode: kVK_DownArrow, modifiers: required))
        XCTAssertEqual(HotkeyManager.mapAction(from: event), .brightnessDown)
    }

    func testContrastMapping() throws {
        let right = try XCTUnwrap(makeEvent(keyCode: kVK_RightArrow, modifiers: required))
        XCTAssertEqual(HotkeyManager.mapAction(from: right), .contrastUp)
        let left = try XCTUnwrap(makeEvent(keyCode: kVK_LeftArrow, modifiers: required))
        XCTAssertEqual(HotkeyManager.mapAction(from: left), .contrastDown)
    }

    func testLetterMappings() throws {
        let eventA = try XCTUnwrap(makeEvent(keyCode: kVK_ANSI_A, modifiers: required))
        XCTAssertEqual(HotkeyManager.mapAction(from: eventA), .toggleAuto)
        let eventW = try XCTUnwrap(makeEvent(keyCode: kVK_ANSI_W, modifiers: required))
        XCTAssertEqual(HotkeyManager.mapAction(from: eventW), .toggleWindow)
    }

    func testMissingModifiersAreIgnored() throws {
        let event = try XCTUnwrap(makeEvent(keyCode: kVK_UpArrow, modifiers: [.control, .command]))
        XCTAssertNil(HotkeyManager.mapAction(from: event))
    }

    func testUnmappedKeyReturnsNil() throws {
        let event = try XCTUnwrap(makeEvent(keyCode: kVK_ANSI_X, modifiers: required))
        XCTAssertNil(HotkeyManager.mapAction(from: event))
    }
}
