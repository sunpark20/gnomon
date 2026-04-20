//
//  BrightnessCard.swift
//  Gnomon
//
//  Phase 4 interactive: slider + tap-to-edit + Auto toggle.
//

import AppKit
import SwiftUI

struct BrightnessCard: View {
    @Bindable var controller: AutoLoopController
    let nextSyncSecondsRemaining: Int
    let onSyncNow: () -> Void
    @State private var isEditingNumber = false
    @State private var editText = ""
    @State private var lastAutoWasOn = true
    @State private var pulseScale: CGFloat = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if controller.autoEnabled {
                syncControls
            }
            valueRow
            slider
            rangeLabels
        }
        .padding(24)
        .frame(minHeight: 200)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .animation(.easeInOut(duration: 0.2), value: controller.autoEnabled)
        .onChange(of: controller.autoEnabled) { _, isOn in
            if !isOn, lastAutoWasOn {
                triggerPulse()
            }
            lastAutoWasOn = isOn
        }
    }

    private var header: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "sun.max")
                    .foregroundStyle(Theme.gold)
                Text("Brightness")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
            }
            Spacer()
            Toggle("Auto", isOn: Binding(
                get: { controller.autoEnabled },
                set: { _ in controller.toggleAuto() }
            ))
            .toggleStyle(.switch)
            .tint(Theme.gold)
            .labelsHidden()
            HStack(spacing: 6) {
                Text("Auto").font(.caption).foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private var current: Int {
        controller.lastSentBrightness ?? controller.targetBrightness
    }

    private var valueRow: some View {
        HStack(alignment: .lastTextBaseline, spacing: 8) {
            if isEditingNumber {
                TextField("0–100", text: $editText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                    .font(.system(size: 32, weight: .heavy))
                    .onSubmit { commitEditedValue() }
                    .onChange(of: editText) { _, newValue in
                        // Auto-commit when the user types a 2-digit value (10–99).
                        // 1-digit or 100 still needs Enter to avoid premature commit.
                        if newValue.count == 2, let value = Int(newValue), (10 ... 99).contains(value) {
                            controller.userSetBrightness(value)
                            isEditingNumber = false
                        }
                    }
            } else {
                Text("\(current)")
                    .font(.system(size: 56, weight: .heavy))
                    .foregroundStyle(Theme.textPrimary)
                    .scaleEffect(pulseScale)
                    .onTapGesture {
                        guard !controller.autoEnabled else { return }
                        editText = String(current)
                        isEditingNumber = true
                    }
            }
            Text("%")
                .font(.title3)
                .foregroundStyle(Theme.textSecondary)
            if controller.autoEnabled, controller.targetBrightness != current {
                Text("→ \(controller.targetBrightness)%")
                    .font(.callout)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.leading, 6)
            }
            if !controller.autoEnabled {
                Text("Auto paused — tap toggle to resume")
                    .font(.caption)
                    .foregroundStyle(Theme.gold.opacity(0.8))
                    .padding(.leading, 6)
            }
        }
    }

    private var slider: some View {
        Slider(
            value: Binding(
                get: { Double(current) },
                set: { newValue in
                    let rounded = Int(newValue)
                    if rounded != current {
                        NSHapticFeedbackManager.defaultPerformer
                            .perform(.alignment, performanceTime: .now)
                    }
                    controller.userSetBrightness(rounded)
                }
            ),
            in: 0 ... 100,
            step: 1
        )
        .tint(Theme.gold)
        .disabled(controller.autoEnabled)
        .opacity(controller.autoEnabled ? 0.5 : 1)
    }

    private var rangeLabels: some View {
        HStack {
            Text("Min").font(.caption2).foregroundStyle(Theme.textSecondary)
            Spacer()
            Text("Max").font(.caption2).foregroundStyle(Theme.textSecondary)
        }
    }

    private var syncControls: some View {
        HStack(spacing: 12) {
            Spacer()
            Button(action: onSyncNow) {
                Label("Sync Now", systemImage: "arrow.clockwise")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.bordered)
            HStack(spacing: 6) {
                Image(systemName: "timer")
                    .foregroundStyle(Theme.textSecondary)
                Text("Next sync in \(max(0, nextSyncSecondsRemaining))s")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .monospacedDigit()
            }
        }
    }

    private func commitEditedValue() {
        if let value = Int(editText) {
            controller.userSetBrightness(value)
        }
        isEditingNumber = false
    }

    private func triggerPulse() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) {
            pulseScale = 1.08
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            withAnimation(.easeOut(duration: 0.2)) {
                pulseScale = 1.0
            }
        }
    }
}
