//
//  SettingsWindow.swift
//  Gnomon
//
//  In-app preferences panel. Opened via the gear icon on the main window
//  header (Phase 10).
//

import AppKit
import SwiftUI

struct SettingsWindow: View {
    @Bindable var controller: AutoLoopController
    @Binding var isPresented: Bool
    @AppStorage("brightnessMin") private var brightnessMin = 20
    @AppStorage("brightnessMax") private var brightnessMax = 95
    @AppStorage("syncIntervalSeconds") private var syncIntervalSeconds = 30

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            hotkeysSection
            brightnessRangeSection
            syncSection
            miscSection
            aboutSection
            Spacer()
        }
        .padding(28)
        .frame(width: 420)
        .frame(minHeight: 600)
        .background(Theme.background)
        .onChange(of: brightnessMin) { _, _ in pushParameters() }
        .onChange(of: brightnessMax) { _, _ in pushParameters() }
        .onChange(of: syncIntervalSeconds) { _, newValue in
            controller.syncInterval = TimeInterval(newValue)
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
            Button(action: { isPresented = false }, label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.textSecondary)
            })
            .buttonStyle(.plain)
        }
    }

    private var hotkeysSection: some View {
        SettingsSection(title: "Hotkeys", iconName: "keyboard") {
            hotkeyRow("Brightness Up", "⌃⌥⌘ ↑")
            hotkeyRow("Brightness Down", "⌃⌥⌘ ↓")
            hotkeyRow("Contrast Up", "⌃⌥⌘ →")
            hotkeyRow("Contrast Down", "⌃⌥⌘ ←")
            hotkeyRow("Toggle Auto", "⌃⌥⌘ A")
            hotkeyRow("Toggle Window", "⌃⌥⌘ W")
        }
    }

    private func hotkeyRow(_ title: String, _ keys: String) -> some View {
        HStack {
            Text(title).font(.callout).foregroundStyle(Theme.textPrimary)
            Spacer()
            Text(keys)
                .font(.system(.caption, design: .monospaced))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Theme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(Theme.textPrimary)
        }
    }

    private var brightnessRangeSection: some View {
        SettingsSection(title: "Brightness Range", iconName: "sun.max") {
            HStack {
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
            HStack {
                Text("Interval").font(.callout).foregroundStyle(Theme.textPrimary)
                Spacer()
                Picker("", selection: $syncIntervalSeconds) {
                    Text("15s").tag(15)
                    Text("30s").tag(30)
                    Text("60s").tag(60)
                    Text("120s").tag(120)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 100)
            }
            HStack {
                Text("Active Monitor").font(.callout).foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(controller.activeMonitor?.displayName ?? "—")
                    .font(.callout)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private var miscSection: some View {
        SettingsSection(title: "Misc", iconName: "wrench.and.screwdriver") {
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
            Text("Gnomon · v1.0.0")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            Text("Ambient-light-driven brightness for your external monitor.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private func openLogsFolder() {
        let url = CSVLogger.defaultLogURL().deletingLastPathComponent()
        NSWorkspace.shared.open(url)
    }
}

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
