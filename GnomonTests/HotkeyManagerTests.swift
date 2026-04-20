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

    override func setUp() {
        super.setUp()
        HotkeyBindingStore.reset()
    }

    func testDefaultBrightnessMapping() throws {
        let manager = HotkeyManager()
        let up = try XCTUnwrap(makeEvent(keyCode: kVK_ANSI_Equal, modifiers: required))
        XCTAssertEqual(manager.mapAction(from: up), .brightnessUp)
        let down = try XCTUnwrap(makeEvent(keyCode: kVK_ANSI_Minus, modifiers: required))
        XCTAssertEqual(manager.mapAction(from: down), .brightnessDown)
    }

    func testDefaultContrastMapping() throws {
        let manager = HotkeyManager()
        let up = try XCTUnwrap(makeEvent(keyCode: kVK_ANSI_RightBracket, modifiers: required))
        XCTAssertEqual(manager.mapAction(from: up), .contrastUp)
        let down = try XCTUnwrap(makeEvent(keyCode: kVK_ANSI_LeftBracket, modifiers: required))
        XCTAssertEqual(manager.mapAction(from: down), .contrastDown)
    }

    func testDefaultTogglesMapping() throws {
        let manager = HotkeyManager()
        let auto = try XCTUnwrap(makeEvent(keyCode: kVK_ANSI_B, modifiers: required))
        XCTAssertEqual(manager.mapAction(from: auto), .toggleAuto)
        let window = try XCTUnwrap(makeEvent(keyCode: kVK_ANSI_G, modifiers: required))
        XCTAssertEqual(manager.mapAction(from: window), .toggleWindow)
    }

    func testMissingModifiersAreIgnored() throws {
        let manager = HotkeyManager()
        let event = try XCTUnwrap(makeEvent(keyCode: kVK_ANSI_Equal, modifiers: [.control, .command]))
        XCTAssertNil(manager.mapAction(from: event))
    }

    func testUnmappedKeyReturnsNil() throws {
        let manager = HotkeyManager()
        let event = try XCTUnwrap(makeEvent(keyCode: kVK_ANSI_X, modifiers: required))
        XCTAssertNil(manager.mapAction(from: event))
    }

    func testCustomBindingOverridesDefault() throws {
        let manager = HotkeyManager()
        let newBinding = KeyBinding(modifiers: required, keyCode: UInt16(kVK_ANSI_X))
        manager.setBinding(newBinding, for: .brightnessUp)

        let event = try XCTUnwrap(makeEvent(keyCode: kVK_ANSI_X, modifiers: required))
        XCTAssertEqual(manager.mapAction(from: event), .brightnessUp)

        // Old default for brightnessUp (=) should no longer trigger it.
        let oldDefault = try XCTUnwrap(makeEvent(keyCode: kVK_ANSI_Equal, modifiers: required))
        XCTAssertNotEqual(manager.mapAction(from: oldDefault), .brightnessUp)
    }

    func testHumanReadableFormat() {
        let binding = KeyBinding(modifiers: [.control, .option, .command], keyCode: UInt16(kVK_ANSI_Equal))
        XCTAssertEqual(binding.humanReadable, "⌃ ⌥ ⌘ =")
    }
}
