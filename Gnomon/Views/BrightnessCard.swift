//
//  BrightnessCard.swift
//  Gnomon
//
//  Right-column top card. Current + target brightness, Auto toggle, slider.
//  Phase 3 renders this read-only. Phase 4 activates the interactions.
//

import SwiftUI

struct BrightnessCard: View {
    let current: Int
    let target: Int
    let autoEnabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "sun.max")
                        .foregroundStyle(Theme.gold)
                    Text("Brightness")
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                }
                Spacer()
                HStack(spacing: 8) {
                    Text("Auto")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                    Circle()
                        .fill(autoEnabled ? Theme.gold : Color.gray.opacity(0.4))
                        .frame(width: 14, height: 14)
                }
            }

            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text("\(current)")
                    .font(.system(size: 56, weight: .heavy))
                    .foregroundStyle(Theme.textPrimary)
                Text("%")
                    .font(.title3)
                    .foregroundStyle(Theme.textSecondary)
                if autoEnabled, target != current {
                    Text("→ \(target) tgt")
                        .font(.callout)
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.leading, 6)
                }
            }

            // Slider is rendered but disabled in Phase 3.
            Slider(value: .constant(Double(current)), in: 0 ... 100)
                .tint(Theme.gold)
                .disabled(true)

            Text("Control overall display luminance.")
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
    BrightnessCard(current: 65, target: 81, autoEnabled: true)
        .padding()
        .frame(width: 500)
        .background(Theme.background)
}
