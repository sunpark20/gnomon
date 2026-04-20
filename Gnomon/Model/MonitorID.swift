//
//  MonitorID.swift
//  Gnomon
//
//  Value type identifying an external monitor addressable by m1ddc.
//

import Foundation

/// Identifies a monitor connected to the Mac and addressable via DDC.
public struct MonitorID: Hashable, Sendable, Identifiable {
    /// The 1-indexed slot number that m1ddc uses in its `display N set …` commands.
    public let slot: Int

    /// Human-readable name reported by m1ddc (e.g. "LG HDR 4K").
    public let displayName: String

    /// UUID or other unique token returned by `m1ddc display list`.
    public let uuid: String

    public var id: String {
        uuid
    }

    public init(slot: Int, displayName: String, uuid: String) {
        self.slot = slot
        self.displayName = displayName
        self.uuid = uuid
    }
}
