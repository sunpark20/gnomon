//
//  BrightnessCard.swift
//  Gnomon
//
//  Phase 4 interactive: slider + tap-to-edit + Auto toggle.
//

import SwiftUI

struct BrightnessCard: View {
    @Bindable var controller: AutoLoopController
    @State private var isEditingNumber = false
    @State private var editText = ""
    @State private var lastAutoWasOn = true
    @State private var pulseScale: CGFloat = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            valueRow
            slider
            subtitle
        }
        .padding(24)
        .frame(minHeight: 200)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
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
            } else {
                Text("\(current)")
                    .font(.system(size: 56, weight: .heavy))
                    .foregroundStyle(Theme.textPrimary)
                    .scaleEffect(pulseScale)
                    .onTapGesture {
                        editText = String(current)
                        isEditingNumber = true
                    }
            }
            Text("%")
                .font(.title3)
                .foregroundStyle(Theme.textSecondary)
            if controller.autoEnabled, controller.targetBrightness != current {
                Text("→ \(controller.targetBrightness) tgt")
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
                set: { controller.userSetBrightness(Int($0)) }
            ),
            in: 0 ... 100,
            step: 1
        )
        .tint(Theme.gold)
    }

    private var subtitle: some View {
        Text("Control overall display luminance.")
            .font(.caption)
            .foregroundStyle(Theme.textSecondary)
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
