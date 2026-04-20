//
//  EMAFilter.swift
//  Gnomon
//
//  Exponential moving average filter.
//  y_n = α × x_n + (1 - α) × y_(n-1)
//
//  PRD §5.3 uses α=0.2 on 1-second lux samples to give ~5s responsiveness.
//
//  Big-delta snap: if |sample − value| stays above snapThreshold for
//  snapDuration consecutive samples, we bypass EMA and jump to sample.
//  Ignores single-frame spikes (person walking past, camera flash) while
//  reacting instantly to genuine scene changes (covered sensor, lights off).
//

import Foundation

public struct EMAFilter: Sendable {
    public let alpha: Double
    public let snapThreshold: Double?
    public let snapDuration: Int
    public private(set) var value: Double?
    /// True iff the most recent `update(_:)` call triggered a snap (bypassed EMA).
    /// Callers use this to decide whether to push an immediate side effect (e.g.
    /// DDC write) instead of waiting for their next scheduled tick.
    public private(set) var didSnapOnLastUpdate = false
    private var consecutiveLargeDeltas = 0

    public init(
        alpha: Double = 0.2,
        snapThreshold: Double? = nil,
        snapDuration: Int = 3
    ) {
        precondition(alpha > 0 && alpha <= 1, "EMA alpha must be in (0, 1]")
        precondition(snapDuration >= 1, "snapDuration must be >= 1")
        self.alpha = alpha
        self.snapThreshold = snapThreshold
        self.snapDuration = snapDuration
    }

    @discardableResult
    public mutating func update(_ sample: Double) -> Double {
        guard let previous = value else {
            value = sample
            didSnapOnLastUpdate = false
            return sample
        }

        if let threshold = snapThreshold, abs(sample - previous) >= threshold {
            consecutiveLargeDeltas += 1
            if consecutiveLargeDeltas >= snapDuration {
                value = sample
                consecutiveLargeDeltas = 0
                didSnapOnLastUpdate = true
                return sample
            }
        } else {
            consecutiveLargeDeltas = 0
        }

        didSnapOnLastUpdate = false
        let next = alpha * sample + (1 - alpha) * previous
        value = next
        return next
    }

    public mutating func reset() {
        value = nil
        consecutiveLargeDeltas = 0
        didSnapOnLastUpdate = false
    }
}
