//
//  AmbientSensorCard.swift
//  Gnomon
//
//  Left-column card. Shows big lux number + gauge + rotating message
//  (witty caption / developer shout).
//

import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

struct AmbientSensorCard: View {
    let lux: Double
    let category: LuxCategory
    let message: DisplayMessage
    var monitorConnected = true

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            // 1. 상단: 타이틀 (중앙 정렬)
            HStack(spacing: 10) {
                macBookBadge
                Text("Mac Sensor")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
            }

            if !monitorConnected {
                disconnectedBadge
                    .padding(.top, 8)
            }

            Spacer(minLength: 0)

            // 2. 중앙: 럭스 수치 (크기 강조)
            VStack(spacing: 0) {
                Text("Current Lux")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.bottom, 4)
                Text(formattedLux)
                    .font(.system(size: 80, weight: .heavy, design: .default))
                    .foregroundStyle(Theme.textPrimary)
                Text("lx")
                    .font(.title3)
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer(minLength: 0)

            // 3. 게이지
            VStack(alignment: .leading, spacing: 6) {
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

            Spacer(minLength: 0)
        }
        .padding(32)
        .overlay(alignment: .bottom) {
            messageView
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
        }
        .frame(minWidth: 260, maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    @ViewBuilder
    private var messageView: some View {
        switch message {
        case let .witty(phrase):
            Text(phrase)
                .font(.callout)
                .foregroundStyle(Theme.textSecondary.opacity(0.8))
                .multilineTextAlignment(.center)
        case let .shout(shout):
            shoutView(shout)
        }
    }

    @ViewBuilder
    private func shoutView(_ shout: DeveloperShout) -> some View {
        switch shout {
        case let .text(body):
            Text(body)
                .font(.callout)
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
        case let .link(title, url):
            Link(destination: url) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.right.square.fill")
                    Text(title).fontWeight(.semibold)
                }
                .font(.callout)
                .foregroundStyle(Theme.gold)
            }
            .buttonStyle(.plain)
        case let .qrCode(title, payload):
            VStack(spacing: 6) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                QRCodeImage(payload: payload)
                    .frame(width: 72, height: 72)
            }
        }
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

    private var disconnectedBadge: some View {
        HStack(spacing: 5) {
            Image(systemName: "bolt.slash.fill")
                .font(.system(size: 11))
            Text("Disconnected")
                .font(.caption2.weight(.medium))
        }
        .foregroundStyle(Theme.textSecondary.opacity(0.6))
        .phaseAnimator([false, true]) { content, phase in
            content.opacity(phase ? 1.0 : 0.15)
        } animation: { _ in
            .easeInOut(duration: 1.0)
        }
    }

    private var gaugeFraction: Double {
        // Log scale mirror of the brightness curve so the bar tracks perception.
        let ceiling = 2000.0
        let normalized = log10(max(0, lux) + 1) / log10(ceiling + 1)
        return min(1, max(0, normalized))
    }
}

private struct QRCodeImage: View {
    let payload: String
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
            } else {
                Color.clear
            }
        }
        .task(id: payload) {
            image = Self.generate(payload: payload)
        }
    }

    private static func generate(payload: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: scaled.extent.size)
    }
}

#Preview("Night") {
    AmbientSensorCard(
        lux: 17,
        category: .veryDim,
        message: .witty("Night-raid-ready illumination. Grab your gear.")
    )
    .padding()
    .background(Theme.background)
}

#Preview("Disconnected") {
    AmbientSensorCard(
        lux: 26,
        category: .dim,
        message: .witty("The Goldshire Inn glows softer than this. Cozy."),
        monitorConnected: false
    )
    .padding()
    .background(Theme.background)
}
