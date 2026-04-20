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
