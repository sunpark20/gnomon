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
