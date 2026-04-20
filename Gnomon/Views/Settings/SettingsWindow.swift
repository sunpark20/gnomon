//
//  SettingsWindow.swift
//  Gnomon
//
//  Preferences sheet. Sections:
//    • Hotkeys — double-click any row to rebind.
//    • Brightness Range — Min/Max numeric fields, Reset.
//    • Sync Options — free-text interval (seconds), active monitor.
//    • Bug Report — opens a prefilled email to the developer.
//    • About — version + description.
//

import AppKit
import SwiftUI

// Settings container aggregates multiple independent sections in one view, so the
// body naturally runs long. Splitting purely to satisfy line count would hurt more
// than it helps.
// swiftlint:disable type_body_length file_length
struct SettingsWindow: View {
    @Bindable var controller: AutoLoopController
    @Environment(\.dismissWindow) private var dismissWindow
    @AppStorage("brightnessMin") private var brightnessMin = 20
    @AppStorage("brightnessMax") private var brightnessMax = 95
    @AppStorage("syncIntervalSeconds") private var syncIntervalSeconds: Double = 30
    @State private var recorderBindings: [HotkeyAction: KeyBinding] = HotkeyBindingStore.load()
    @State private var recordingAction: HotkeyAction?
    @State private var intervalText = "30"
    @State private var minText = "20"
    @State private var maxText = "95"
    @State private var emailCopied = false
    @FocusState private var intervalFocused: Bool
    @FocusState private var minFocused: Bool
    @FocusState private var maxFocused: Bool

    private let bugReportEmail = "coastguard2681@gmail.com"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                hotkeysSection
                brightnessRangeSection
                syncSection
                bugReportSection
                aboutSection
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 480, idealWidth: 480, minHeight: 900, idealHeight: 1080)
        .background(Theme.background)
        .onChange(of: brightnessMin) { _, newValue in
            minText = String(newValue)
            pushParameters()
        }
        .onChange(of: brightnessMax) { _, newValue in
            maxText = String(newValue)
            pushParameters()
        }
        .onChange(of: syncIntervalSeconds) { _, newValue in
            controller.syncInterval = newValue
            intervalText = Self.formatInterval(newValue)
            // Immediate apply + reset timer so user sees the change take
            // effect without waiting for the previous cycle to finish.
            controller.intervalDidChange()
        }
        .onChange(of: intervalFocused) { _, isFocused in
            // Autocommit when the field loses focus, so tabbing or clicking
            // elsewhere (including the X button) applies the pending value.
            if !isFocused { commitIntervalText() }
        }
        .onChange(of: minFocused) { _, isFocused in
            if !isFocused { commitMinText() }
        }
        .onChange(of: maxFocused) { _, isFocused in
            if !isFocused { commitMaxText() }
        }
        .onAppear {
            intervalText = Self.formatInterval(syncIntervalSeconds)
            minText = String(brightnessMin)
            maxText = String(brightnessMax)
        }
        .onDisappear {
            // Safety net: window is closing. Commit anything still pending.
            commitIntervalText()
            commitMinText()
            commitMaxText()
        }
    }

    private var intervalIsPending: Bool {
        intervalText.trimmingCharacters(in: .whitespaces) != Self.formatInterval(syncIntervalSeconds)
    }

    private var minIsPending: Bool {
        minText.trimmingCharacters(in: .whitespaces) != String(brightnessMin)
    }

    private var maxIsPending: Bool {
        maxText.trimmingCharacters(in: .whitespaces) != String(brightnessMax)
    }

    /// Renders `30` as "30", `0.5` as "0.5", `12.3456` as "12.35".
    private static func formatInterval(_ value: Double) -> String {
        if value.rounded() == value {
            return String(format: "%.0f", value)
        }
        return String(format: "%.2f", value).trimmingTrailingZeros()
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
                    onCancel: { recordingAction = nil },
                    onClear: {
                        recorderBindings[action] = .disabled
                        HotkeyBindingStore.save(recorderBindings)
                        NotificationCenter.default.post(name: .gnomonHotkeysChanged, object: nil)
                        recordingAction = nil
                    }
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
            HStack(alignment: .top) {
                rangeField(
                    title: "Min",
                    text: $minText,
                    isFocused: $minFocused,
                    isPending: minIsPending,
                    onSubmit: commitMinText
                )
                rangeField(
                    title: "Max",
                    text: $maxText,
                    isFocused: $maxFocused,
                    isPending: maxIsPending,
                    onSubmit: commitMaxText
                )
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

    private func rangeField(
        title: String,
        text: Binding<String>,
        isFocused: FocusState<Bool>.Binding,
        isPending: Bool,
        onSubmit: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(Theme.textSecondary)
            TextField("", text: text)
                .textFieldStyle(.roundedBorder)
                .frame(width: 70)
                .focused(isFocused)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isPending ? Theme.gold : Color.clear, lineWidth: 2)
                        .animation(.easeInOut(duration: 0.15), value: isPending)
                )
                .onSubmit(onSubmit)
            pendingHint(isPending: isPending)
        }
    }

    /// Fixed-height slot so showing/hiding the hint doesn't shift surrounding layout.
    private func pendingHint(isPending: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "return")
                .font(.caption2)
            Text("Enter로 적용")
                .font(.caption2)
        }
        .foregroundStyle(Theme.gold)
        .opacity(isPending ? 1 : 0)
    }

    private var syncSection: some View {
        SettingsSection(title: "Sync Options", iconName: "arrow.triangle.2.circlepath") {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Interval (seconds)").font(.caption).foregroundStyle(Theme.textSecondary)
                    TextField("30", text: $intervalText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                        .focused($intervalFocused)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(intervalIsPending ? Theme.gold : Color.clear, lineWidth: 2)
                                .animation(.easeInOut(duration: 0.15), value: intervalIsPending)
                        )
                        .onSubmit { commitIntervalText() }
                    pendingHint(isPending: intervalIsPending)
                }
                VStack {
                    HStack(spacing: 6) {
                        ForEach([0.5, 5.0, 30.0, 60.0, 300.0], id: \.self) { preset in
                            Button(Self.formatInterval(preset) + "s") {
                                syncIntervalSeconds = preset
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .padding(.top, 18)
                    Spacer(minLength: 0)
                }
                Spacer()
            }
            Text(intervalTip)
                .font(.caption2)
                .foregroundStyle(intervalTipColor)
                .italic(syncIntervalSeconds < 1 || syncIntervalSeconds > 3600)

            Text("인터벌과 상관없이 급격한 조도 변화는 즉시 반영됩니다.")
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var bugReportSection: some View {
        SettingsSection(title: "Bug Report", iconName: "ladybug") {
            HStack {
                Button("Open Logs Folder") {
                    openLogsFolder()
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Theme.gold)
                Spacer()
            }
            HStack(spacing: 6) {
                Text("Email")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                Button(action: copyBugReportEmail) {
                    HStack(spacing: 4) {
                        Text(bugReportEmail)
                        Image(systemName: emailCopied ? "checkmark" : "doc.on.doc")
                    }
                    .font(.caption)
                    .foregroundStyle(Theme.gold)
                }
                .buttonStyle(.plain)
                .help(emailCopied ? "Copied!" : "Click to copy")
                Spacer()
            }
        }
    }

    private var aboutSection: some View {
        SettingsSection(title: "About", iconName: "info.circle") {
            Text("Gnomon · v1.1.0")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    // MARK: - Helpers

    private var intervalTip: String {
        if syncIntervalSeconds < 1 {
            return "여기 클럽인가요?? 모니터가 고장나도 책임지지 않아요."
        }
        if syncIntervalSeconds > 3600 {
            return "당신은 영생을 사는 존재이십니까? 이렇게 느리게 리프레쉬 되도 정말 괜찮아요?"
        }
        return "소수점도 OK (예: 0.5초). 제한 없음."
    }

    private var intervalTipColor: Color {
        if syncIntervalSeconds < 1 || syncIntervalSeconds > 3600 {
            return Theme.gold
        }
        return Theme.textSecondary
    }

    private func commitIntervalText() {
        let trimmed = intervalText.trimmingCharacters(in: .whitespaces)
        if let value = Double(trimmed), value > 0 {
            syncIntervalSeconds = value
            intervalText = Self.formatInterval(value)
        } else {
            intervalText = Self.formatInterval(syncIntervalSeconds)
        }
    }

    private func commitMinText() {
        let trimmed = minText.trimmingCharacters(in: .whitespaces)
        if let value = Int(trimmed), value >= 0, value < brightnessMax {
            brightnessMin = value
        }
        minText = String(brightnessMin)
    }

    private func commitMaxText() {
        let trimmed = maxText.trimmingCharacters(in: .whitespaces)
        if let value = Int(trimmed), value <= 100, value > brightnessMin {
            brightnessMax = value
        }
        maxText = String(brightnessMax)
    }

    private func pushParameters() {
        let clampedMin = max(0, min(brightnessMin, brightnessMax - 1))
        let clampedMax = max(clampedMin + 1, min(brightnessMax, 100))
        controller.parameters = BrightnessCurve.Parameters(
            minBrightness: clampedMin,
            maxBrightness: clampedMax,
            luxCeiling: controller.parameters.luxCeiling,
            darkFloorLux: controller.parameters.darkFloorLux
        )
    }

    private func openLogsFolder() {
        let url = CSVLogger.defaultLogURL().deletingLastPathComponent()
        NSWorkspace.shared.open(url)
    }

    private func copyBugReportEmail() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(bugReportEmail, forType: .string)
        emailCopied = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1500))
            emailCopied = false
        }
    }
}

// swiftlint:enable type_body_length

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
