//
//  AmbientSensorCard.swift
//  Gnomon
//
//  Left-column card. Shows big lux number + gauge + witty caption.
//

import SwiftUI

struct AmbientSensorCard: View {
    let lux: Double
    let category: LuxCategory
    let wittyPhrase: String

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 8) {
                Image(systemName: "sun.max.fill")
                    .foregroundStyle(Theme.gold)
                Text("Ambient Sensor")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
            }

            Spacer(minLength: 0)

            VStack(alignment: .center, spacing: 4) {
                Text("Current Lux")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(formattedLux)
                        .font(.system(size: 56, weight: .heavy, design: .default))
                        .foregroundStyle(Theme.textPrimary)
                    Text("lx")
                        .font(.title3)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Dark").font(.caption2).foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text("Bright").font(.caption2).foregroundStyle(Theme.textSecondary)
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.gold.opacity(0.15))
                        Capsule()
                            .fill(LinearGradient(
                                colors: [Theme.gold.opacity(0.6), Theme.gold],
                                startPoint: .leading,
                                endPoint: .trailing
                            ))
                            .frame(width: max(8, proxy.size.width * gaugeFraction))
                    }
                }
                .frame(height: 8)
            }

            Text(wittyPhrase)
                .italic()
                .font(.callout)
                .foregroundStyle(Theme.textSecondary.opacity(0.8))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(minWidth: 260, minHeight: 440)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private var formattedLux: String {
        String(format: "%.0f", max(0, lux))
    }

    private var gaugeFraction: Double {
        // Log scale mirror of the brightness curve so the bar tracks perception.
        let ceiling = 2000.0
        let normalized = log10(max(0, lux) + 1) / log10(ceiling + 1)
        return min(1, max(0, normalized))
    }
}

#Preview("Day") {
    AmbientSensorCard(
        lux: 428,
        category: .office,
        wittyPhrase: "전형적인 사무실 조명입니다."
    )
    .padding()
    .background(Theme.background)
}
