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
    @State private var onboarding = OnboardingViewModel()
    @AppStorage("onboardingCompletedAt") private var onboardingCompletedAt: Double = 0

    var body: some Scene {
        WindowGroup("Gnomon", id: "main") {
            Group {
                if onboardingCompletedAt > 0 {
                    MainWindow(controller: controller)
                        .background(WindowAccessor { window in
                            WindowManager.shared.register(window)
                        })
                        .background(FrameAutosave(name: "GnomonMainWindow"))
                        .task {
                            await controller.start()
                            wireHotkeys()
                        }
                } else {
                    OnboardingWindow(viewModel: onboarding) {
                        onboardingCompletedAt = Date().timeIntervalSince1970
                    }
                }
            }
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 840, height: 540)

        Window("Gnomon Settings", id: "settings") {
            SettingsWindow(controller: controller)
                .background(FrameAutosave(name: "GnomonSettingsWindow"))
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 460, height: 740)
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

        NotificationCenter.default.addObserver(
            forName: .gnomonHotkeysChanged,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                hotkeys.stop()
                hotkeys = HotkeyManager()
                wireHotkeys()
            }
        }
    }
}

extension Notification.Name {
    static let gnomonToggleWindow = Notification.Name("com.sunguk.gnomon.toggleWindow")
    static let gnomonAutoStateChanged = Notification.Name("com.sunguk.gnomon.autoStateChanged")
    static let gnomonHotkeysChanged = Notification.Name("com.sunguk.gnomon.hotkeysChanged")
}
