//
//  WindowManager.swift
//  Gnomon
//
//  Tracks all Gnomon NSWindows (main + settings).
//
//  Cmd+W is intercepted to hide (orderOut) instead of close, keeping the
//  window alive for instant re-show. If the user clicks the traffic-light
//  close button, SwiftUI fully destroys the window; in that case we
//  trigger "File > New Gnomon Window" to let SwiftUI recreate it.
//

import AppKit
import Carbon.HIToolbox
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
    private var cmdWMonitor: Any?

    public func register(_ window: NSWindow, id: WindowID) {
        window.isReleasedWhenClosed = false
        entries[id] = Entry(window: window, wasVisible: window.isVisible)
        installCmdWMonitor()
    }

    private func installCmdWMonitor() {
        guard cmdWMonitor == nil else { return }
        cmdWMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.contains(.command),
                  event.keyCode == UInt16(kVK_ANSI_W) else { return event }
            event.window?.orderOut(nil)
            return nil
        }
    }

    /// Hides every tracked window if any is visible, otherwise restores them.
    public func toggle() {
        let anyVisible = entries.values.contains { $0.window?.isVisible == true }
        if anyVisible {
            hideAll()
        } else {
            showAll()
        }
    }

    /// Brings the main window forward, recreating it if the user closed it.
    public func show() {
        bringAppForward()
        if let w = entries[.main]?.window {
            w.makeKeyAndOrderFront(nil)
        } else {
            reopenViaSwiftUI()
        }
    }

    private func hideAll() {
        for (key, entry) in entries {
            guard let window = entry.window else { continue }
            entries[key]?.wasVisible = window.isVisible
            if window.isVisible { window.orderOut(nil) }
        }
    }

    /// Main window always comes back; Settings only if it was open when hidden.
    private func showAll() {
        show()
        if let w = entries[.settings]?.window, entries[.settings]?.wasVisible == true {
            w.makeKeyAndOrderFront(nil)
        }
    }

    private func reopenViaSwiftUI() {
        guard let fileMenu = NSApp.mainMenu?.item(withTitle: "File")?.submenu else { return }
        for item in fileMenu.items where item.title.contains("New") && item.title.contains("Gnomon") {
            _ = item.target?.perform(item.action, with: item)
            return
        }
    }

    private func bringAppForward() {
        NSApp.activate(ignoringOtherApps: true)
    }
}
