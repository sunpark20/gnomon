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
    private var controller: AutoLoopController {
        appDelegate.controller
    }

    @State private var onboarding = OnboardingViewModel()
    @AppStorage("onboardingCompletedAt") private var onboardingCompletedAt: Double = 0

    var body: some Scene {
        WindowGroup(Self.mainWindowTitle, id: "main") {
            Group {
                if GnomonAppDelegate.isHostedTest {
                    EmptyView()
                } else if onboardingCompletedAt > 0 {
                    MainWindow(controller: controller)
                        .background(WindowAccessor { window in
                            WindowManager.shared.register(window, id: .main)
                        })
                        .background(FrameAutosave(name: "GnomonMainWindow"))
                } else {
                    OnboardingWindow(viewModel: onboarding) {
                        onboardingCompletedAt = Date().timeIntervalSince1970
                        appDelegate.startControls()
                    }
                    .frame(width: 520, height: 580)
                    .background(WindowAccessor { window in
                        window.setContentSize(NSSize(width: 520, height: 580))
                        window.center()
                    })
                }
            }
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1000, height: 620)

        Window("Gnomon Settings", id: "settings") {
            SettingsWindow(controller: controller)
                .background(WindowAccessor { window in
                    WindowManager.shared.register(window, id: .settings)
                })
                .background(FrameAutosave(name: "GnomonSettingsWindow.v5"))
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 480, height: 900)
    }

    private static var mainWindowTitle: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        guard let version, !version.isEmpty else { return "Gnomon" }
        return "Gnomon \(version)"
    }
}

extension Notification.Name {
    static let gnomonToggleWindow = Notification.Name("com.sunguk.gnomon.toggleWindow")
    static let gnomonAutoStateChanged = Notification.Name("com.sunguk.gnomon.autoStateChanged")
    static let gnomonHotkeysChanged = Notification.Name("com.sunguk.gnomon.hotkeysChanged")
}
