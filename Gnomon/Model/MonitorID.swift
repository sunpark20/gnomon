//
//  MonitorID.swift
//  Gnomon
//
//  Value type identifying an external monitor addressable via DDC.
//

import Foundation

/// Identifies a monitor connected to the Mac and addressable via DDC.
public struct MonitorID: Hashable, Sendable, Identifiable {
    /// The 1-indexed slot number in discovery order.
    public let slot: Int

    /// Human-readable name (e.g. "LG HDR 4K").
    public let displayName: String

    /// IOKit registry entry ID (as string) for native DDC.
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
