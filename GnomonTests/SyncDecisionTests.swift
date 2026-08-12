//
//  SyncDecisionTests.swift
//  GnomonTests
//
//  Pure tests for the sync decision seam — no async loops, no sleeps.
//

import XCTest
@testable import Gnomon

final class SyncDecisionTests: XCTestCase {
    private func input(
        autoEnabled: Bool = true,
        isPaused: Bool = false,
        force: Bool = false,
        target: Int = 50,
        lastSent: Int? = 50,
        deadband: Int = 2
    ) -> SyncDecision.Input {
        SyncDecision.Input(
            autoEnabled: autoEnabled,
            isPaused: isPaused,
            force: force,
            target: target,
            lastSent: lastSent,
            deadband: deadband
        )
    }

    func testDisabledWhenAutoOff() {
        XCTAssertEqual(SyncDecision.evaluate(input(autoEnabled: false, target: 50, lastSent: 40)), .disabled)
    }

    func testDisabledWhenPaused() {
        XCTAssertEqual(SyncDecision.evaluate(input(isPaused: true, target: 50, lastSent: 40)), .disabled)
    }

    func testGateBeatsForce() {
        // Pause/auto-off takes priority over force: no automatic write.
        XCTAssertEqual(SyncDecision.evaluate(input(autoEnabled: false, force: true)), .disabled)
    }

    func testWritesWhenNothingSentYet() {
        XCTAssertEqual(SyncDecision.evaluate(input(target: 50, lastSent: nil)), .write(50))
    }

    func testForceWritesEvenWithinDeadband() {
        XCTAssertEqual(SyncDecision.evaluate(input(force: true, target: 50, lastSent: 50)), .write(50))
    }

    func testUnchangedWithinDeadband() {
        XCTAssertEqual(SyncDecision.evaluate(input(target: 51, lastSent: 50)), .unchanged)
    }

    func testWritesWhenDeltaMeetsDeadband() {
        XCTAssertEqual(SyncDecision.evaluate(input(target: 52, lastSent: 50)), .write(52))
    }

    func testWritesOnLargeDropWithinGate() {
        XCTAssertEqual(SyncDecision.evaluate(input(target: 10, lastSent: 80)), .write(10))
    }
}
