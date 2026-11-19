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
    let controller = AutoLoopController()
    private let hotkeys = HotkeyManager()
    private var controlsTask: Task<Void, Never>?
    private var toggleWindowObserver: NSObjectProtocol?

    static var isHostedTest: Bool {
        NSClassFromString("XCTestCase") != nil || Bundle.main.bundleIdentifier?.hasSuffix(".GnomonTestHost") == true
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.isHostedTest else { return }
        if let bundleId = Bundle.main.bundleIdentifier {
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
            if running.count > 1 {
                for app in running where app != .current {
                    app.activate()
                }
                NSApp.terminate(nil)
                return
            }
        }

        if UserDefaults.standard.double(forKey: "onboardingCompletedAt") > 0 {
            startControls()
        }

        let controller = StatusBarController()
        statusBar = controller
        StatusBarProxy.shared.statusBarController = controller
        StatusBarProxy.shared.onLeftClick = {
            WindowManager.shared.toggle()
        }

        let updater = IconUpdater()
        updater.start(in: controller.rawItem)
        iconUpdater = updater

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            await UpdateChecker.shared.checkOnLaunch()
        }

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

    func startControls() {
        guard controlsTask == nil else { return }
        wireHotkeys()
        controlsTask = Task { [controller] in
            await controller.start()
        }
    }

    private func wireHotkeys() {
        hotkeys.onAction = { [controller] action in
            switch action {
            case .brightnessUp:
                let base = controller.lastSentBrightness ?? controller.targetBrightness
                controller.userSetBrightness(base + 5)
            case .brightnessDown:
                let base = controller.lastSentBrightness ?? controller.targetBrightness
                controller.userSetBrightness(base - 5)
            case .contrastUp:
                controller.userSetContrast(controller.contrast + 5)
            case .contrastDown:
                controller.userSetContrast(controller.contrast - 5)
            case .toggleAuto:
                controller.toggleAuto()
            case .toggleWindow:
                NotificationCenter.default.post(name: .gnomonToggleWindow, object: nil)
            }
        }
        hotkeys.start()
    }

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        true
    }

    public func applicationWillTerminate(_ notification: Notification) {
        controlsTask?.cancel()
        controller.stop()
        hotkeys.stop()
        iconUpdater?.stop()
        if let observer = toggleWindowObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
