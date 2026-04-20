//
//  SettingsWindow.swift
//  Gnomon
//
//  Preferences sheet. Sections:
//    • Hotkeys — double-click any row to rebind.
//    • Brightness Range — Min/Max numeric fields, Reset.
//    • Sync Options — free-text interval (seconds), active monitor.
//    • Utilities — open logs folder, quit.
//    • About — version + description.
//

import AppKit
import SwiftUI

struct SettingsWindow: View {
    @Bindable var controller: AutoLoopController
    @Environment(\.dismissWindow) private var dismissWindow
    @AppStorage("brightnessMin") private var brightnessMin = 20
    @AppStorage("brightnessMax") private var brightnessMax = 95
    @AppStorage("syncIntervalSeconds") private var syncIntervalSeconds = 30
    @State private var recorderBindings: [HotkeyAction: KeyBinding] = HotkeyBindingStore.load()
    @State private var recordingAction: HotkeyAction?
    @State private var intervalText = "30"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                hotkeysSection
                brightnessRangeSection
                syncSection
                utilitiesSection
                aboutSection
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 460, idealWidth: 460, minHeight: 740, idealHeight: 740)
        .background(Theme.background)
        .onChange(of: brightnessMin) { _, _ in pushParameters() }
        .onChange(of: brightnessMax) { _, _ in pushParameters() }
        .onChange(of: syncIntervalSeconds) { _, newValue in
            controller.syncInterval = TimeInterval(newValue)
            intervalText = String(newValue)
        }
        .onAppear {
            intervalText = String(syncIntervalSeconds)
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading) {
                Text("Gnomon")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundStyle(Theme.textPrimary)
                Text("Settings & Preferences")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Button(action: { dismissWindow() }, label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.textSecondary)
            })
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
        }
    }

    private var hotkeysSection: some View {
        SettingsSection(title: "Hotkeys", iconName: "keyboard") {
            Text("Double-click a row to reassign. Press ESC to cancel.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            ForEach(HotkeyAction.allCases, id: \.self) { action in
                let current = recorderBindings[action] ?? KeyBinding.defaults[action] ?? KeyBinding(
                    modifiers: [.control, .option, .command],
                    keyCode: 0
                )
                HotkeyRow(
                    action: action,
                    binding: current,
                    isRecording: recordingAction == action,
                    onStartRecording: { recordingAction = action },
                    onCaptured: { captured in
                        recorderBindings[action] = captured
                        HotkeyBindingStore.save(recorderBindings)
                        NotificationCenter.default.post(name: .gnomonHotkeysChanged, object: nil)
                        recordingAction = nil
                    },
                    onCancel: { recordingAction = nil }
                )
            }
            HStack {
                Spacer()
                Button("Reset to Defaults") {
                    HotkeyBindingStore.reset()
                    recorderBindings = KeyBinding.defaults
                    NotificationCenter.default.post(name: .gnomonHotkeysChanged, object: nil)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Theme.gold)
            }
        }
    }

    private var brightnessRangeSection: some View {
        SettingsSection(title: "Brightness Range", iconName: "sun.max") {
            HStack(alignment: .bottom) {
                rangeField(title: "Min", value: $brightnessMin)
                rangeField(title: "Max", value: $brightnessMax)
                Spacer()
                Button("Reset") {
                    brightnessMin = 20
                    brightnessMax = 95
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Theme.gold)
            }
        }
    }

    private func rangeField(title: String, value: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(Theme.textSecondary)
            TextField("", value: value, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 70)
        }
    }

    private var syncSection: some View {
        SettingsSection(title: "Sync Options", iconName: "arrow.triangle.2.circlepath") {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Interval (seconds)").font(.caption).foregroundStyle(Theme.textSecondary)
                    TextField("30", text: $intervalText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                        .onSubmit { commitIntervalText() }
                }
                HStack(spacing: 6) {
                    ForEach([15, 30, 60, 120], id: \.self) { preset in
                        Button("\(preset)s") { syncIntervalSeconds = preset }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
                Spacer()
            }
            Text("Tip: any value between 5 and 3600 seconds.")
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)

            HStack {
                Text("Active Monitor").font(.callout).foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(controller.activeMonitor?.displayName ?? "—")
                    .font(.callout)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private var utilitiesSection: some View {
        SettingsSection(title: "Utilities", iconName: "wrench.and.screwdriver") {
            HStack {
                Button("Open Logs Folder") {
                    openLogsFolder()
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Theme.gold)
                Spacer()
                Button("Quit Gnomon") {
                    NSApp.terminate(nil)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
            }
        }
    }

    private var aboutSection: some View {
        SettingsSection(title: "About", iconName: "info.circle") {
            Text("Gnomon · v1.1.0")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            Text("Ambient-light-driven brightness for your external monitor.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    // MARK: - Helpers

    private func commitIntervalText() {
        let trimmed = intervalText.trimmingCharacters(in: .whitespaces)
        if let value = Int(trimmed) {
            let clamped = max(5, min(3600, value))
            syncIntervalSeconds = clamped
            intervalText = String(clamped)
        } else {
            intervalText = String(syncIntervalSeconds)
        }
    }

    private func pushParameters() {
        let clampedMin = max(0, min(brightnessMin, brightnessMax - 1))
        let clampedMax = max(clampedMin + 1, min(brightnessMax, 100))
        controller.parameters = BrightnessCurve.Parameters(
            minBrightness: clampedMin,
            maxBrightness: clampedMax,
            luxCeiling: controller.parameters.luxCeiling
        )
    }

    private func openLogsFolder() {
        let url = CSVLogger.defaultLogURL().deletingLastPathComponent()
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Hotkey row

private struct HotkeyRow: View {
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
private struct HotkeyRecorder: NSViewRepresentable {
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

// MARK: - Container

private struct SettingsSection<Content: View>: View {
    let title: String
    let iconName: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .foregroundStyle(Theme.gold)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
            }
            VStack(alignment: .leading, spacing: 10) {
                content
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}
