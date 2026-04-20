//
//  BrightnessCurve.swift
//  Gnomon
//
//  Maps ambient light (lux) → target monitor brightness %.
//
//  Formula (PRD §5.2.1, v0.4 confirmed):
//      b(lux) = b_min + (b_max - b_min) × clamp(log10(lux + 1) / log10(ceiling + 1), 0, 1)
//
//  Rationale (research/adaptive-curves.md §1):
//      Weber-Fechner perception = logarithmic. 2000 lux ceiling covers
//      bright-indoor to light-daylight range without early saturation.
//

import Foundation

public enum BrightnessCurve {
    /// Default parameter set matching PRD v0.4 confirmed values.
    public struct Parameters: Sendable, Equatable {
        public var minBrightness: Int
        public var maxBrightness: Int
        public var luxCeiling: Double
        /// Lux at or below which the sensor is treated as fully dark → returns minBrightness.
        /// macOS returns ~1–3 lux even with the sensor completely covered, so a strict
        /// Below this lux the curve returns b_min directly.
        /// 15 lux covers dark-room / covered-sensor scenarios on Apple Silicon.
        public var darkFloorLux: Double

        public init(
            minBrightness: Int = 0,
            maxBrightness: Int = 100,
            luxCeiling: Double = 2000,
            darkFloorLux: Double = 15
        ) {
            self.minBrightness = minBrightness
            self.maxBrightness = maxBrightness
            self.luxCeiling = luxCeiling
            self.darkFloorLux = darkFloorLux
        }

        public static let `default` = Parameters()
    }

    /// Computes target brightness percent for a given lux reading.
    /// Returned value is clamped to [minBrightness, maxBrightness] and rounded to nearest Int.
    public static func target(lux: Double, parameters: Parameters = .default) -> Int {
        let safeLux = max(0, lux)
        if safeLux <= parameters.darkFloorLux {
            return parameters.minBrightness
        }
        let numerator = log10(safeLux + 1)
        let denominator = log10(parameters.luxCeiling + 1)
        let normalized = max(0, min(1, numerator / denominator))

        let span = Double(parameters.maxBrightness - parameters.minBrightness)
        let exact = Double(parameters.minBrightness) + span * normalized
        return Int(exact.rounded())
    }
}
