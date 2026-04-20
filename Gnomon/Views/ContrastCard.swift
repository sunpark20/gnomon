//
//  ContrastCard.swift
//  Gnomon
//
//  Manual-only contrast slider (PRD §5.2.2). No Auto toggle.
//

import SwiftUI

struct ContrastCard: View {
    let value: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
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

            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text("\(value)")
                    .font(.system(size: 48, weight: .heavy))
                    .foregroundStyle(Theme.textPrimary)
                Text("%")
                    .font(.title3)
                    .foregroundStyle(Theme.textSecondary)
            }

            Slider(value: .constant(Double(value)), in: 0 ... 100)
                .tint(Theme.gold)
                .disabled(true)

            HStack {
                Text("Min").font(.caption2).foregroundStyle(Theme.textSecondary)
                Spacer()
                Text("Max").font(.caption2).foregroundStyle(Theme.textSecondary)
            }

            Text("Adjust tonal dynamic range. Factory default suggested.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(24)
        .frame(minHeight: 200)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

#Preview {
    ContrastCard(value: 70)
        .padding()
        .frame(width: 500)
        .background(Theme.background)
}
