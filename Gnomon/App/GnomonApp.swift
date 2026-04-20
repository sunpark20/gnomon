//
//  GnomonApp.swift
//  Gnomon
//
//  Ambient-light-based external monitor brightness controller for macOS.
//

import SwiftUI

@main
struct GnomonApp: App {
    @NSApplicationDelegateAdaptor(GnomonAppDelegate.self) private var appDelegate
    @State private var controller = AutoLoopController()
    @State private var hotkeys = HotkeyManager()

    var body: some Scene {
        WindowGroup {
            MainWindow(controller: controller)
                .background(WindowAccessor { window in
                    WindowManager.shared.register(window)
                })
                .task {
                    await controller.start()
                    wireHotkeys()
                }
        }
        .windowResizability(.contentSize)
    }

    @MainActor
    private func wireHotkeys() {
        hotkeys.onAction = { action in
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
}

extension Notification.Name {
    static let gnomonToggleWindow = Notification.Name("com.sunguk.gnomon.toggleWindow")
}
