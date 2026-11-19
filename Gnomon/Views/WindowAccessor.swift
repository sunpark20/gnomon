//
//  WindowAccessor.swift
//  Gnomon
//
//  SwiftUI bridge that hands the underlying NSWindow to the caller exactly
//  once after the view has been embedded in a window. Used to register the
//  main window with WindowManager.
//

import AppKit
import SwiftUI

struct WindowAccessor: NSViewRepresentable {
    let onWindow: @MainActor (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                MainActor.assumeIsolated {
                    onWindow(window)
                }
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Attaches a frame autosave name to the underlying NSWindow so macOS
/// restores its position and size on next launch.
struct FrameAutosave: NSViewRepresentable {
    let name: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                guard let window = view.window else { return }
                window.setFrameAutosaveName(name)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Window occlusion also covers windows ordered out by the menu bar shortcut.
struct WindowVisibilityReader: NSViewRepresentable {
    @Binding var isVisible: Bool

    func makeNSView(context: Context) -> VisibilityView {
        let view = VisibilityView()
        view.report = { visible in
            if isVisible != visible { isVisible = visible }
        }
        return view
    }

    func updateNSView(_ view: VisibilityView, context: Context) {}

    static func dismantleNSView(_ view: VisibilityView, coordinator: Void) {
        view.report = nil
        view.stopObserving()
    }

    final class VisibilityView: NSView {
        var report: ((Bool) -> Void)?
        private var observers: [NSObjectProtocol] = []

        func stopObserving() {
            for observer in observers {
                NotificationCenter.default.removeObserver(observer)
            }
            observers.removeAll()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopObserving()
            if let window {
                for name in [
                    NSWindow.didChangeOcclusionStateNotification,
                    NSWindow.didMiniaturizeNotification,
                    NSWindow.didDeminiaturizeNotification,
                ] {
                    observe(name, object: window)
                }
                for name in [NSApplication.didHideNotification, NSApplication.didUnhideNotification] {
                    observe(name, object: NSApp)
                }
            }
            // Attaching the view can happen during a SwiftUI update. Publish after that update completes.
            Task { @MainActor [weak self] in self?.reportVisibility() }
        }

        private func observe(_ name: Notification.Name, object: AnyObject) {
            let center = NotificationCenter.default
            let token = center.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.reportVisibility() }
            }
            observers.append(token)
        }

        private func reportVisibility() {
            let visible = window.map { $0.isVisible && !$0.isMiniaturized && $0.occlusionState.contains(.visible) }
            report?(visible == true && !NSApp.isHidden)
        }
    }
}
