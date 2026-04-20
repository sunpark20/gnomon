//
//  StringFormat.swift
//  Gnomon
//
//  Small string helpers used across the app.
//

import Foundation

extension String {
    /// Removes trailing zeros after a decimal point while preserving at least
    /// one digit. "30.00" → "30", "12.50" → "12.5", "0.100" → "0.1".
    func trimmingTrailingZeros() -> String {
        guard contains(".") else { return self }
        var result = self
        while result.last == "0" {
            result.removeLast()
        }
        if result.last == "." {
            result.removeLast()
        }
        return result
    }
}
