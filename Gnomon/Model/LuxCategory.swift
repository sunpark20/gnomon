//
//  LuxCategory.swift
//  Gnomon
//
//  Maps a raw lux reading to a semantic category used for the witty label
//  (PRD §5.5.1) and for UI color gradient hints.
//

import Foundation

public enum LuxCategory: CaseIterable, Sendable {
    case pitchDark
    case veryDim
    case dimIndoor
    case office
    case bright
    case softDaylight
    case directSunlight

    public static func classify(_ lux: Double) -> LuxCategory {
        switch lux {
        case ..<10: .pitchDark
        case 10 ..< 50: .veryDim
        case 50 ..< 200: .dimIndoor
        case 200 ..< 500: .office
        case 500 ..< 1000: .bright
        case 1000 ..< 2000: .softDaylight
        default: .directSunlight
        }
    }

    /// Normalized position 0.0 (dark) → 1.0 (bright) for progress bar rendering.
    public var displayName: String {
        switch self {
        case .pitchDark: "Pitch Dark"
        case .veryDim: "Very Dim"
        case .dimIndoor: "Dim Indoor"
        case .office: "Office"
        case .bright: "Bright"
        case .softDaylight: "Soft Daylight"
        case .directSunlight: "Direct Sunlight"
        }
    }
}
