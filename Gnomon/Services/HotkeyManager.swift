//
//  HotkeyManager.swift
//  Gnomon
//
//  Global hotkey dispatcher using NSEvent.addGlobalMonitorForEvents.
//  Requires Accessibility permission (check AccessibilityChecker).
//
//  PRD §5.5 mapping:
//    ⌃⌥⌘ ↑/↓ : brightness ±5
//    ⌃⌥⌘ ←/→ : contrast ±5
//    ⌃⌥⌘  A  : toggle Auto
//    ⌃⌥⌘  W  : toggle window
//

import AppKit
import Carbon.HIToolbox

@MainActor
public final class HotkeyManager {
    public enum Action: Sendable {
        case brightnessUp
        case brightnessDown
        case contrastUp
        case contrastDown
        case toggleAuto
        case toggleWindow
    }

    public var onAction: ((Action) -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?

    public init() {}

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

    // Intentionally no deinit cleanup — Swift 6 strict concurrency forbids
    // accessing non-Sendable stored properties from a nonisolated deinit.
    // HotkeyManager's lifetime is tied to the app, and callers must call
    // stop() explicitly if they want to tear down earlier.

    private func handle(_ event: NSEvent) {
        guard let action = Self.mapAction(from: event) else { return }
        onAction?(action)
    }

    /// Decodes modifier + keyCode into one of our `Action` values.
    /// Exposed `internal` so it can be unit tested.
    static func mapAction(from event: NSEvent) -> Action? {
        let required: NSEvent.ModifierFlags = [.control, .option, .command]
        let masked = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard masked.contains(required) else { return nil }

        switch Int(event.keyCode) {
        case kVK_UpArrow: return .brightnessUp
        case kVK_DownArrow: return .brightnessDown
        case kVK_RightArrow: return .contrastUp
        case kVK_LeftArrow: return .contrastDown
        case kVK_ANSI_A: return .toggleAuto
        case kVK_ANSI_W: return .toggleWindow
        default: return nil
        }
    }
}
