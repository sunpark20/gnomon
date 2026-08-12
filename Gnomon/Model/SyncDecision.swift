//
//  SyncDecision.swift
//  Gnomon
//
//  Pure decision for the sync loop: given the current control state, decide
//  whether to write brightness, skip it (within deadband), or stay disabled.
//
//  Side effects — display I/O, logging, timers — live in AutoLoopController.
//  This is the seam that concentrates the disabled / force / deadband priority
//  in one place so it can be exercised without driving the async loops.
//

import Foundation

/// Outcome of deciding whether the sync loop should push a brightness write.
enum SyncDecision: Equatable {
    /// Auto is off or paused — the controller performs no automatic write.
    case disabled
    /// Target is within the deadband of the last sent value — skip the write,
    /// but treat it as a successful (no-op) sync.
    case unchanged
    /// Write this brightness value to the active display.
    case write(Int)

    /// Snapshot of the control state the decision reads from.
    ///
    /// Monitor acquisition is deliberately absent. The controller does that I/O
    /// only after `evaluate` returns non-`.disabled`, preserving the original
    /// ordering: gate → acquire monitor → apply this decision.
    struct Input {
        var autoEnabled: Bool
        var isPaused: Bool
        var force: Bool
        var target: Int
        var lastSent: Int?
        var deadband: Int
    }

    /// Decides the sync outcome from the current control state.
    ///
    /// Priority: the disabled gate first, then an unconditional write when
    /// `force` is set or nothing has been sent yet, then the deadband compare.
    static func evaluate(_ input: Input) -> SyncDecision {
        guard input.autoEnabled, !input.isPaused else { return .disabled }
        guard let last = input.lastSent else { return .write(input.target) }
        if input.force || abs(input.target - last) >= input.deadband {
            return .write(input.target)
        }
        return .unchanged
    }
}
