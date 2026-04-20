//
//  AppDelegate.swift
//  Gnomon
//
//  Owns the status bar icon and wires up hotkey → window plumbing.
//

import AppKit
import Combine
import Foundation

@MainActor
public final class GnomonAppDelegate: NSObject, NSApplicationDelegate {
    public private(set) var statusBar: StatusBarController?
    public private(set) var iconUpdater: IconUpdater?
    private var toggleWindowObserver: NSObjectProtocol?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = StatusBarController()
        statusBar = controller
        StatusBarProxy.shared.statusBarController = controller
        StatusBarProxy.shared.onLeftClick = {
            WindowManager.shared.toggle()
        }

        NSApp.setActivationPolicy(.accessory)

        let updater = IconUpdater()
        updater.statusItem = controller.rawItem
        updater.start()
        iconUpdater = updater

        toggleWindowObserver = NotificationCenter.default.addObserver(
            forName: .gnomonToggleWindow,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                WindowManager.shared.toggle()
            }
        }
    }

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows {
            WindowManager.shared.show()
        }
        return true
    }

    public func applicationWillTerminate(_ notification: Notification) {
        if let observer = toggleWindowObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
