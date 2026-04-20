//
//  EMAFilter.swift
//  Gnomon
//
//  Exponential moving average filter.
//  y_n = α × x_n + (1 - α) × y_(n-1)
//
//  PRD §5.3 uses α=0.2 on 1-second lux samples to give ~5s responsiveness.
//

import Foundation

public struct EMAFilter: Sendable {
    public let alpha: Double
    public private(set) var value: Double?

    public init(alpha: Double = 0.2) {
        precondition(alpha > 0 && alpha <= 1, "EMA alpha must be in (0, 1]")
        self.alpha = alpha
    }

    @discardableResult
    public mutating func update(_ sample: Double) -> Double {
        let previous = value ?? sample
        let next = alpha * sample + (1 - alpha) * previous
        value = next
        return next
    }

    public mutating func reset() {
        value = nil
    }
}
