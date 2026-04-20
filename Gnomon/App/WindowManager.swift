//
//  WindowManager.swift
//  Gnomon
//
//  Tracks all Gnomon NSWindows (main + settings). The Toggle Window hotkey
//  hides every currently-visible Gnomon window and brings back whichever
//  windows were visible the last time toggle was fired — so if the user had
//  Settings open alongside Main, both re-appear together.
//

import AppKit
import Foundation

@MainActor
public final class WindowManager {
    public static let shared = WindowManager()

    public enum WindowID: String {
        case main
        case settings
    }

    private struct Entry {
        weak var window: NSWindow?
        var wasVisible = false
    }

    private var entries: [WindowID: Entry] = [:]

    public func register(_ window: NSWindow, id: WindowID) {
        window.isReleasedWhenClosed = false
        entries[id] = Entry(window: window, wasVisible: window.isVisible)
    }

    // MARK: - Main-only legacy helpers

    /// Legacy. Kept for callers that don't need multi-window logic.
    public func toggle() {
        toggleAll()
    }

    public func show() {
        bringAppForward()
        entries[.main]?.window?.makeKeyAndOrderFront(nil)
    }

    public func hide() {
        entries[.main]?.window?.orderOut(nil)
    }

    // MARK: - Multi-window toggle

    /// If any Gnomon window is currently visible, hide them all.
    /// If none are visible, show whichever windows were visible at the
    /// previous hide — defaulting to main if nothing was remembered.
    public func toggleAll() {
        let anyVisible = entries.values.contains { $0.window?.isVisible == true }
        if anyVisible {
            hideAll()
        } else {
            showRememberedOrMain()
        }
    }

    private func hideAll() {
        for (key, entry) in entries {
            guard let window = entry.window else { continue }
            // Snapshot current visibility before we hide.
            entries[key] = Entry(window: window, wasVisible: window.isVisible)
            if window.isVisible {
                window.orderOut(nil)
            }
        }
    }

    private func showRememberedOrMain() {
        bringAppForward()
        var shownAny = false
        for (_, entry) in entries {
            guard let window = entry.window, entry.wasVisible else { continue }
            window.makeKeyAndOrderFront(nil)
            shownAny = true
        }
        if !shownAny {
            entries[.main]?.window?.makeKeyAndOrderFront(nil)
        }
    }

    private func bringAppForward() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
