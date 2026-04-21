//
//  Theme.swift
//  Gnomon
//
//  Beige + gold palette matching the Stitch mockup.
//

import SwiftUI

enum Theme {
    static let background = Color(red: 245 / 255, green: 239 / 255, blue: 224 / 255)
    static let cardBackground = Color.white.opacity(0.6)
    static let gold = Color(red: 156 / 255, green: 128 / 255, blue: 67 / 255)
    static let goldDark = Color(red: 120 / 255, green: 95 / 255, blue: 48 / 255)
    static let textPrimary = Color(red: 58 / 255, green: 45 / 255, blue: 20 / 255)
    static let textSecondary = Color(red: 120 / 255, green: 105 / 255, blue: 85 / 255)
}

struct GoldSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0 ... 100
    var step: Double = 1
    var disabled: Bool = false
    var onChanged: ((Double) -> Void)?

    var body: some View {
        GeometryReader { proxy in
            let fraction = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
            let thumbX = proxy.size.width * fraction
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.textSecondary.opacity(0.2))
                    .frame(height: 6)
                Capsule()
                    .fill(LinearGradient(
                        colors: [Theme.gold.opacity(0.6), Theme.gold],
                        startPoint: .leading,
                        endPoint: .trailing
                    ))
                    .frame(width: max(0, thumbX), height: 6)
                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                    .frame(width: 20, height: 20)
                    .offset(x: max(0, min(thumbX - 10, proxy.size.width - 20)))
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        guard !disabled else { return }
                        let ratio = max(0, min(1, drag.location.x / proxy.size.width))
                        let stepped = (ratio * (range.upperBound - range.lowerBound) / step).rounded() * step + range.lowerBound
                        let clamped = max(range.lowerBound, min(range.upperBound, stepped))
                        if clamped != value {
                            value = clamped
                            onChanged?(clamped)
                        }
                    }
            )
        }
        .frame(height: 20)
        .opacity(disabled ? 0.5 : 1)
    }
}

struct GoldToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer()
            Capsule()
                .fill(configuration.isOn
                    ? AnyShapeStyle(LinearGradient(
                        colors: [Theme.gold.opacity(0.6), Theme.gold],
                        startPoint: .leading,
                        endPoint: .trailing
                    ))
                    : AnyShapeStyle(Theme.textSecondary.opacity(0.3))
                )
                .frame(width: 40, height: 24)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle()
                        .fill(.white)
                        .shadow(radius: 1)
                        .padding(2)
                }
                .animation(.easeInOut(duration: 0.15), value: configuration.isOn)
                .onTapGesture { configuration.isOn.toggle() }
        }
    }
}
