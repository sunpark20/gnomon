//
//  ContrastCard.swift
//  Gnomon
//
//  Phase 5 interactive manual-only contrast slider (PRD §5.2.2).
//

import SwiftUI

struct ContrastCard: View {
    @Bindable var controller: AutoLoopController
    @State private var isEditingNumber = false
    @State private var editText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            valueRow
            slider
            rangeLabels
            subtitle
        }
        .padding(24)
        .frame(minHeight: 200)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "circle.righthalf.filled")
                .foregroundStyle(Theme.gold)
            Text("Contrast")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Text("Manual")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var valueRow: some View {
        HStack(alignment: .lastTextBaseline, spacing: 6) {
            if isEditingNumber {
                TextField("0–100", text: $editText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                    .font(.system(size: 32, weight: .heavy))
                    .onSubmit { commit() }
                    .onChange(of: editText) { _, newValue in
                        if newValue.count == 2, let value = Int(newValue), (10 ... 99).contains(value) {
                            controller.userSetContrast(value)
                            isEditingNumber = false
                        }
                    }
            } else {
                Text("\(controller.contrast)")
                    .font(.system(size: 48, weight: .heavy))
                    .foregroundStyle(Theme.textPrimary)
                    .onTapGesture {
                        editText = String(controller.contrast)
                        isEditingNumber = true
                    }
            }
            Text("%")
                .font(.title3)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var slider: some View {
        Slider(
            value: Binding(
                get: { Double(controller.contrast) },
                set: { controller.userSetContrast(Int($0)) }
            ),
            in: 0 ... 100,
            step: 1
        )
        .tint(Theme.gold)
    }

    private var rangeLabels: some View {
        HStack {
            Text("Min").font(.caption2).foregroundStyle(Theme.textSecondary)
            Spacer()
            Text("Max").font(.caption2).foregroundStyle(Theme.textSecondary)
        }
    }

    private var subtitle: some View {
        Text("Adjust tonal dynamic range. Factory default suggested.")
            .font(.caption)
            .foregroundStyle(Theme.textSecondary)
    }

    private func commit() {
        if let value = Int(editText) {
            controller.userSetContrast(value)
        }
        isEditingNumber = false
    }
}
