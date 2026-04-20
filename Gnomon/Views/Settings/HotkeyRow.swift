//
//  HotkeyRow.swift
//  Gnomon
//
//  One row in Settings → Hotkeys. Double-click to start recording a new
//  binding; ESC cancels; any chord with at least one modifier is accepted.
//

import AppKit
import SwiftUI

struct HotkeyRow: View {
    let action: HotkeyAction
    let binding: KeyBinding
    let isRecording: Bool
    let onStartRecording: () -> Void
    let onCaptured: (KeyBinding) -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack {
            Text(action.displayName)
                .font(.callout)
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            ZStack {
                if isRecording {
                    HotkeyRecorder(
                        onCaptured: onCaptured,
                        onCancel: onCancel
                    )
                    .frame(width: 120, height: 28)
                } else {
                    Text(binding.humanReadable)
                        .font(.system(.caption, design: .monospaced))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Theme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .foregroundStyle(Theme.textPrimary)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { if !isRecording { onStartRecording() } }
    }
}

/// Transient view that captures a keyDown event and returns the resulting
/// KeyBinding via callback. Shown inline when a row is "recording".
struct HotkeyRecorder: NSViewRepresentable {
    let onCaptured: (KeyBinding) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = RecorderNSView()
        view.onCaptured = onCaptured
        view.onCancel = onCancel
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let view = nsView as? RecorderNSView {
            view.onCaptured = onCaptured
            view.onCancel = onCancel
        }
    }

    final class RecorderNSView: NSView {
        var onCaptured: ((KeyBinding) -> Void)?
        var onCancel: (() -> Void)?

        override var acceptsFirstResponder: Bool {
            true
        }

        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)
            let path = NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6)
            NSColor.systemOrange.withAlphaComponent(0.15).setFill()
            path.fill()
            let text = NSAttributedString(
                string: "Press keys…",
                attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                    .foregroundColor: NSColor.systemOrange,
                ]
            )
            let size = text.size()
            text.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2))
        }

        override func keyDown(with event: NSEvent) {
            if event.keyCode == 53 { // ESC
                onCancel?()
                return
            }
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            // Require at least one modifier to avoid trapping plain keys.
            let filtered = modifiers.intersection([.control, .option, .command, .shift])
            guard !filtered.isEmpty else { return }
            onCaptured?(KeyBinding(modifiers: filtered, keyCode: event.keyCode))
        }
    }
}
