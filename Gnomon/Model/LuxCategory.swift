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
}
