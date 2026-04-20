//
//  HotkeyManager.swift
//  Gnomon
//
//  Global hotkey dispatcher using NSEvent.addGlobalMonitorForEvents.
//  Requires Accessibility permission (check AccessibilityChecker).
//
//  Default bindings (PRD §5.5, v0.6 revised):
//    ⌃⌥⌘ = / -  : brightness ±5
//    ⌃⌥⌘ ] / [  : contrast ±5
//    ⌃⌥⌘ A     : toggle Auto
//    ⌃⌥⌘ G     : toggle window
//
//  Users can rebind any action by double-clicking its row in Settings.
//

import AppKit
import Carbon.HIToolbox

public enum HotkeyAction: String, CaseIterable, Sendable, Codable {
    case brightnessUp
    case brightnessDown
    case contrastUp
    case contrastDown
    case toggleAuto
    case toggleWindow

    public var displayName: String {
        switch self {
        case .brightnessUp: "Brightness Up"
        case .brightnessDown: "Brightness Down"
        case .contrastUp: "Contrast Up"
        case .contrastDown: "Contrast Down"
        case .toggleAuto: "Toggle Auto"
        case .toggleWindow: "Toggle Window"
        }
    }
}

public struct KeyBinding: Sendable, Codable, Equatable {
    public let modifierRawValue: UInt
    public let keyCode: UInt16

    public var modifiers: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifierRawValue)
    }

    public init(modifiers: NSEvent.ModifierFlags, keyCode: UInt16) {
        modifierRawValue = modifiers.rawValue
        self.keyCode = keyCode
    }

    /// The three-modifier combo Gnomon uses by default for every hotkey.
    public static let controlOptionCommand: NSEvent.ModifierFlags = [.control, .option, .command]

    public static let defaults: [HotkeyAction: KeyBinding] = [
        .brightnessUp: KeyBinding(modifiers: controlOptionCommand, keyCode: UInt16(kVK_ANSI_Equal)),
        .brightnessDown: KeyBinding(modifiers: controlOptionCommand, keyCode: UInt16(kVK_ANSI_Minus)),
        .contrastUp: KeyBinding(modifiers: controlOptionCommand, keyCode: UInt16(kVK_ANSI_RightBracket)),
        .contrastDown: KeyBinding(modifiers: controlOptionCommand, keyCode: UInt16(kVK_ANSI_LeftBracket)),
        .toggleAuto: KeyBinding(modifiers: controlOptionCommand, keyCode: UInt16(kVK_ANSI_B)),
        .toggleWindow: KeyBinding(modifiers: controlOptionCommand, keyCode: UInt16(kVK_ANSI_G)),
    ]

    /// Human-readable form like "⌃⌥⌘ =" used in Settings.
    public var humanReadable: String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.option) { parts.append("⌥") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        if modifiers.contains(.command) { parts.append("⌘") }
        parts.append(KeyBinding.keyName(for: Int(keyCode)))
        return parts.joined(separator: " ")
    }

    /// Best-effort printable name for a virtual keyCode.
    public static func keyName(for keyCode: Int) -> String {
        if let special = specialKeyName(for: keyCode) { return special }
        if let letter = letterKeyName(for: keyCode) { return letter }
        if let digit = digitKeyName(for: keyCode) { return digit }
        return "?\(keyCode)"
    }

    // swiftlint:disable:next cyclomatic_complexity
    private static func specialKeyName(for keyCode: Int) -> String? {
        switch keyCode {
        case kVK_UpArrow: "↑"
        case kVK_DownArrow: "↓"
        case kVK_LeftArrow: "←"
        case kVK_RightArrow: "→"
        case kVK_ANSI_Equal: "="
        case kVK_ANSI_Minus: "-"
        case kVK_ANSI_LeftBracket: "["
        case kVK_ANSI_RightBracket: "]"
        case kVK_ANSI_Semicolon: ";"
        case kVK_ANSI_Quote: "'"
        case kVK_ANSI_Comma: ","
        case kVK_ANSI_Period: "."
        case kVK_ANSI_Slash: "/"
        case kVK_ANSI_Backslash: "\\"
        case kVK_ANSI_Grave: "`"
        case kVK_Space: "Space"
        case kVK_Return: "↵"
        case kVK_Tab: "⇥"
        case kVK_Escape: "⎋"
        case kVK_Delete: "⌫"
        default: nil
        }
    }

    // swiftlint:disable:next cyclomatic_complexity
    private static func letterKeyName(for keyCode: Int) -> String? {
        switch keyCode {
        case kVK_ANSI_A: "A"
        case kVK_ANSI_B: "B"
        case kVK_ANSI_C: "C"
        case kVK_ANSI_D: "D"
        case kVK_ANSI_E: "E"
        case kVK_ANSI_F: "F"
        case kVK_ANSI_G: "G"
        case kVK_ANSI_H: "H"
        case kVK_ANSI_I: "I"
        case kVK_ANSI_J: "J"
        case kVK_ANSI_K: "K"
        case kVK_ANSI_L: "L"
        case kVK_ANSI_M: "M"
        case kVK_ANSI_N: "N"
        case kVK_ANSI_O: "O"
        case kVK_ANSI_P: "P"
        case kVK_ANSI_Q: "Q"
        case kVK_ANSI_R: "R"
        case kVK_ANSI_S: "S"
        case kVK_ANSI_T: "T"
        case kVK_ANSI_U: "U"
        case kVK_ANSI_V: "V"
        case kVK_ANSI_W: "W"
        case kVK_ANSI_X: "X"
        case kVK_ANSI_Y: "Y"
        case kVK_ANSI_Z: "Z"
        default: nil
        }
    }

    private static func digitKeyName(for keyCode: Int) -> String? {
        switch keyCode {
        case kVK_ANSI_0: "0"
        case kVK_ANSI_1: "1"
        case kVK_ANSI_2: "2"
        case kVK_ANSI_3: "3"
        case kVK_ANSI_4: "4"
        case kVK_ANSI_5: "5"
        case kVK_ANSI_6: "6"
        case kVK_ANSI_7: "7"
        case kVK_ANSI_8: "8"
        case kVK_ANSI_9: "9"
        default: nil
        }
    }
}

/// Persistence helper for per-action bindings.
public enum HotkeyBindingStore {
    private static let defaultsKey = "hotkeyBindings.v1"

    public static func load() -> [HotkeyAction: KeyBinding] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else {
            return KeyBinding.defaults
        }
        if let decoded = try? JSONDecoder().decode([String: KeyBinding].self, from: data) {
            var result = KeyBinding.defaults
            for (key, value) in decoded {
                if let action = HotkeyAction(rawValue: key) {
                    result[action] = value
                }
            }
            return result
        }
        return KeyBinding.defaults
    }

    public static func save(_ bindings: [HotkeyAction: KeyBinding]) {
        var dict: [String: KeyBinding] = [:]
        for (action, binding) in bindings {
            dict[action.rawValue] = binding
        }
        if let data = try? JSONEncoder().encode(dict) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    public static func reset() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }
}

@MainActor
public final class HotkeyManager {
    public var onAction: ((HotkeyAction) -> Void)?

    public private(set) var bindings: [HotkeyAction: KeyBinding]

    private var globalMonitor: Any?
    private var localMonitor: Any?

    public init() {
        bindings = HotkeyBindingStore.load()
    }

    public func start() {
        stop()
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in self?.handle(event) }
            return event
        }
    }

    public func stop() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }

    public func setBinding(_ binding: KeyBinding, for action: HotkeyAction) {
        bindings[action] = binding
        HotkeyBindingStore.save(bindings)
    }

    public func resetToDefaults() {
        HotkeyBindingStore.reset()
        bindings = KeyBinding.defaults
    }

    private func handle(_ event: NSEvent) {
        guard let action = mapAction(from: event) else { return }
        onAction?(action)
    }

    /// Matches the event against current user bindings.
    public func mapAction(from event: NSEvent) -> HotkeyAction? {
        let masked = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        for (action, binding) in bindings {
            if binding.keyCode == event.keyCode,
               masked.intersection([.control, .option, .command, .shift]) == binding.modifiers
            {
                return action
            }
        }
        return nil
    }
}
