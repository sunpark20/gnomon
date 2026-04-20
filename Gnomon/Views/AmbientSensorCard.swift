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
            HStack(spacing: 10) {
                macBookBadge
                VStack(alignment: .leading, spacing: 2) {
                    Text("MacBook Sensor")
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                    Text("내장 조도센서 (Ambient Light)")
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                }
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

    /// Stylised MacBook silhouette with a glowing dot at the sensor location
    /// (top-center of the lid, where the camera module sits).
    private var macBookBadge: some View {
        ZStack(alignment: .top) {
            Image(systemName: "laptopcomputer")
                .font(.system(size: 26))
                .foregroundStyle(Theme.textPrimary)
            Circle()
                .fill(Theme.gold)
                .frame(width: 5, height: 5)
                .shadow(color: Theme.gold.opacity(0.9), radius: 4)
                .shadow(color: Theme.gold.opacity(0.6), radius: 10)
                .offset(y: 3)
                .opacity(0.4 + min(1, pulseIntensity) * 0.6)
                .animation(.easeInOut(duration: 1.6).repeatForever(), value: pulseIntensity)
        }
        .frame(width: 36, height: 28)
    }

    /// Pulse intensity mapped to lux so the sensor dot glows brighter when the
    /// sensor is actually reading a strong signal — tiny but satisfying.
    private var pulseIntensity: Double {
        min(1, log10(max(1, lux)) / log10(2001))
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
