//
//  WindowManager.swift
//  Gnomon
//
//  Tracks the main window and lets it be shown/hidden without terminating
//  the app. Invoked by the menu bar icon and by the ⌃⌥⌘+W hotkey.
//

import AppKit
import Foundation

@MainActor
public final class WindowManager {
    public static let shared = WindowManager()

    private weak var managedWindow: NSWindow?

    public func register(_ window: NSWindow) {
        managedWindow = window
        window.isReleasedWhenClosed = false
    }

    public func toggle() {
        guard let window = managedWindow else {
            bringAppForward()
            return
        }
        if window.isVisible, NSApp.isActive {
            window.orderOut(nil)
        } else {
            bringAppForward()
            window.makeKeyAndOrderFront(nil)
        }
    }

    public func show() {
        bringAppForward()
        managedWindow?.makeKeyAndOrderFront(nil)
    }

    public func hide() {
        managedWindow?.orderOut(nil)
    }

    private func bringAppForward() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
