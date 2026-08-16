//
//  SettingsWindow.swift
//  Gnomon
//
//  Preferences sheet. Sections:
//    • Hotkeys — double-click any row to rebind.
//    • Brightness Range — Min/Max numeric fields, Reset.
//    • Sync Options — free-text interval (seconds), active monitor.
//    • Bug Report — opens the public GitHub form.
//    • About — version + description.
//

import AppKit
import ReportKit
import SwiftUI

// Settings container aggregates multiple independent sections in one view, so the
// body naturally runs long. Splitting purely to satisfy line count would hurt more
// than it helps.
// swiftlint:disable type_body_length file_length
struct SettingsWindow: View {
    @Bindable var controller: AutoLoopController
    @Environment(\.dismissWindow) private var dismissWindow
    @AppStorage("brightnessMin") private var brightnessMin = 0
    @AppStorage("brightnessMax") private var brightnessMax = 100
    @AppStorage("darkFloorLux") private var darkFloorLux: Double = 15
    @AppStorage("syncIntervalSeconds") private var syncIntervalSeconds: Double = 30
    @State private var recorderBindings: [HotkeyAction: KeyBinding] = HotkeyBindingStore.load()
    @State private var recordingAction: HotkeyAction?
    @State private var intervalText = "30"
    @State private var minText = "0"
    @State private var maxText = "100"
    @State private var darkFloorText = "15"
    @State private var reportStatus: String?
    @FocusState private var intervalFocused: Bool
    @FocusState private var minFocused: Bool
    @FocusState private var maxFocused: Bool
    @FocusState private var darkFloorFocused: Bool

    private static let reportTarget = ReportTarget(
        appID: "gnomon",
        displayName: "Gnomon",
        template: "gnomon-bug.yml"
    )

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                hotkeysSection
                brightnessRangeSection
                syncSection
                bugReportSection
                UpdatesSection()
                aboutSection
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 480, idealWidth: 480, idealHeight: 900)
        .background(Theme.background)
        .onChange(of: brightnessMin) { _, newValue in
            minText = String(newValue)
            pushParameters()
        }
        .onChange(of: brightnessMax) { _, newValue in
            maxText = String(newValue)
            pushParameters()
        }
        .onChange(of: darkFloorLux) { _, newValue in
            darkFloorText = Self.formatInterval(newValue)
            pushParameters()
        }
        .onChange(of: darkFloorFocused) { _, isFocused in
            if !isFocused { commitDarkFloorText() }
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
            darkFloorText = Self.formatInterval(darkFloorLux)
        }
        .onDisappear {
            commitIntervalText()
            commitMinText()
            commitMaxText()
            commitDarkFloorText()
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

    private var darkFloorIsPending: Bool {
        darkFloorText.trimmingCharacters(in: .whitespaces) != Self.formatInterval(darkFloorLux)
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
                    brightnessMin = 0
                    brightnessMax = 100
                    darkFloorLux = 15
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Theme.gold)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Calibration — Dark Floor Lux").font(.caption).foregroundStyle(Theme.textSecondary)
                        HStack(spacing: 4) {
                            TextField("15", text: $darkFloorText)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 70)
                                .focused($darkFloorFocused)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(darkFloorIsPending ? Theme.gold : Color.clear, lineWidth: 2)
                                        .animation(.easeInOut(duration: 0.15), value: darkFloorIsPending)
                                )
                                .onSubmit { commitDarkFloorText() }
                                .onKeyPress(.escape) { darkFloorFocused = false
                                    return .handled
                                }
                            Text("lx")
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                            pendingHint(isPending: darkFloorIsPending)
                        }
                    }
                    Spacer()
                }
                Text(BrightnessCurve.darkFloorCalibrationTip)
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
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
                .onKeyPress(.escape) { isFocused.wrappedValue = false
                    return .handled
                }
            pendingHint(isPending: isPending)
        }
    }

    /// Fixed-height slot so showing/hiding the hint doesn't shift surrounding layout.
    private func pendingHint(isPending: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "return")
                .font(.caption2)
            Text("Press Enter")
                .font(.caption2)
        }
        .foregroundStyle(Theme.gold)
        .opacity(isPending ? 1 : 0)
    }

    private var syncSection: some View {
        SettingsSection(title: "Sync Options", iconName: "arrow.triangle.2.circlepath") {
            VStack(alignment: .leading, spacing: 4) {
                Text("Brightness Sync Interval").font(.caption).foregroundStyle(Theme.textSecondary)
                HStack(spacing: 4) {
                    TextField("30", text: $intervalText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                        .focused($intervalFocused)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(intervalIsPending ? Theme.gold : Color.clear, lineWidth: 2)
                                .animation(.easeInOut(duration: 0.15), value: intervalIsPending)
                        )
                        .onSubmit { commitIntervalText() }
                        .onKeyPress(.escape) { intervalFocused = false
                            return .handled
                        }
                    Text("s")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                    ForEach([5.0, 30.0, 60.0, 300.0], id: \.self) { preset in
                        Button(Self.formatInterval(preset) + "s") {
                            syncIntervalSeconds = preset
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
            ZStack(alignment: .topLeading) {
                Group {
                    Text(Self.tipTooFast)
                    Text(Self.tipTooSlow)
                    Text(Self.tipDefault)
                }
                .hidden()
                Text(intervalTip)
                    .foregroundStyle(intervalTipColor)
                    .italic(syncIntervalSeconds < 1 || syncIntervalSeconds > 3600)
            }
            .font(.caption2)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var bugReportSection: some View {
        SettingsSection(title: "Bug Report", iconName: "ladybug", trailing: {
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
            Text("v\(version)")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }, content: {
            Text("GitHub reports are public. Do not include personal information or raw logs.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            HStack(spacing: 8) {
                Button(action: openGitHubReport) {
                    Label("Report on GitHub", systemImage: "ladybug")
                        .font(.caption)
                }
                .buttonStyle(.borderedProminent)
            }
            Text("Reports open in your browser and may require a GitHub account.")
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
            HStack(spacing: 6) {
                Button(action: { openLogsFolder() }, label: {
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                        Text("Open Logs Folder")
                    }
                    .font(.caption)
                    .foregroundStyle(Theme.gold)
                })
                .buttonStyle(.plain)
                .help("Review and redact logs before sharing them")
                Spacer()
                Button(action: {
                    if let url = URL(string: "https://homeninja.vercel.app/#gnomon") {
                        NSWorkspace.shared.open(url)
                    }
                }, label: {
                    Image(systemName: "house")
                        .font(.caption)
                        .foregroundStyle(Theme.gold)
                })
                .buttonStyle(.plain)
                .help("Homepage")
            }
            if let reportStatus {
                Text(reportStatus)
                    .font(.caption2)
                    .foregroundStyle(Theme.gold)
            }
        })
    }

    private var aboutSection: some View {
        SettingsSection(title: "About", iconName: "info.circle") {
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
            let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
            Text("Gnomon · v\(version) (\(build))")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            Text("Bug reports use one shared public GitHub tracker.")
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    // MARK: - Helpers

    private static let tipTooFast = "Too fast — may damage your monitor."
    private static let tipTooSlow = "Very slow — brightness may feel out of sync."
    private static let tipDefault = "Sudden light changes apply instantly, regardless of sync interval."

    private var intervalTip: String {
        if syncIntervalSeconds < 1 { return Self.tipTooFast }
        if syncIntervalSeconds > 3600 { return Self.tipTooSlow }
        return Self.tipDefault
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

    private func commitDarkFloorText() {
        let trimmed = darkFloorText.trimmingCharacters(in: .whitespaces)
        if let value = Double(trimmed), value >= 0 {
            darkFloorLux = value
            darkFloorText = Self.formatInterval(value)
        } else {
            darkFloorText = Self.formatInterval(darkFloorLux)
        }
    }

    private func pushParameters() {
        let clampedMin = max(0, min(brightnessMin, brightnessMax - 1))
        let clampedMax = max(clampedMin + 1, min(brightnessMax, 100))
        controller.parameters = BrightnessCurve.Parameters(
            minBrightness: clampedMin,
            maxBrightness: clampedMax,
            luxCeiling: controller.parameters.luxCeiling,
            darkFloorLux: darkFloorLux
        )
    }

    private func openLogsFolder() {
        let url = CSVLogger.defaultLogURL().deletingLastPathComponent()
        NSWorkspace.shared.open(url)
    }

    private func openGitHubReport() {
        guard let link = Self.reportTarget.github(metadata: .current()) else {
            reportStatus = "Could not create the report link."
            return
        }
        showReportStatus(for: ReportOpener.open(link))
    }

    private func showReportStatus(for status: ReportOpener.Status) {
        guard let message = status.userMessage else {
            reportStatus = nil
            return
        }
        reportStatus = message
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            reportStatus = nil
        }
    }
}

// swiftlint:enable type_body_length

// MARK: - Container

struct SettingsSection<Trailing: View, Content: View>: View {
    let title: String
    let iconName: String
    let trailing: Trailing
    @ViewBuilder var content: Content

    init(title: String, iconName: String, @ViewBuilder trailing: () -> Trailing, @ViewBuilder content: () -> Content) {
        self.title = title
        self.iconName = iconName
        self.trailing = trailing()
        self.content = content()
    }

    init(title: String, iconName: String, @ViewBuilder content: () -> Content) where Trailing == EmptyView {
        self.title = title
        self.iconName = iconName
        trailing = EmptyView()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .foregroundStyle(Theme.gold)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                trailing
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
