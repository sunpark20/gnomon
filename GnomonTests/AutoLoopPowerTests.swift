import AppKit
import XCTest
@testable import Gnomon

extension AutoLoopControllerTests {
    func testRegularSyncRecoversAfterDDCReadFailuresWithoutDisplayEvent() async throws {
        let state = AutoLoopFakeState()
        let controller = makeController(state: state)
        controller.syncInterval = 0.08
        controller.disconnectedRetryInterval = .milliseconds(80)
        await controller.start()
        defer { controller.stop() }
        try await waitUntil { controller.nextSyncAt != nil }

        await state.failNextBrightnessReads(4)
        controller.parameters = .init(minBrightness: 65, maxBrightness: 65)
        try await waitUntil { !controller.monitorConnected }
        XCTAssertNil(controller.nextSyncAt)
        try await waitUntil { controller.lastSentBrightness == 65 && controller.nextSyncAt != nil }
    }

    func testTransientReadbackFailureDoesNotRepeatBrightnessWrite() async throws {
        let state = AutoLoopFakeState()
        let controller = makeController(state: state)
        await controller.start()
        defer { controller.stop() }
        try await waitUntil { controller.nextSyncAt != nil }
        let originalSync = controller.lastSyncAt
        await state.clearWrites()
        await state.failNextBrightnessReads(1)
        controller.applyNow()
        try await waitUntil { controller.lastSyncAt != originalSync }
        let writes = await state.writes
        XCTAssertEqual(writes, [50])
    }

    func testRetryContinuesAfterWakeAttemptsRunOutAndStopsWhenPausedOrAsleep() async throws {
        let state = AutoLoopFakeState(monitors: [])
        let controller = makeController(state: state)
        controller.displayRecoveryDelays = [.zero]
        controller.disconnectedRetryInterval = .milliseconds(50)
        await controller.start()
        defer { controller.stop() }
        controller.startDisplayRecovery(reason: "screen-wake")
        // Startup, the last wake attempt, then the first periodic retry.
        try await waitUntil { await state.listCalls >= 3 }
        controller.togglePause()
        let calls = await state.listCalls
        try await Task.sleep(for: .milliseconds(160))
        let pausedCalls = await state.listCalls
        XCTAssertEqual(pausedCalls, calls)

        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
        controller.togglePause()
        try await Task.sleep(for: .milliseconds(160))
        let sleepingCalls = await state.listCalls
        let reads = await state.luxReads
        XCTAssertEqual(sleepingCalls, calls)
        XCTAssertEqual(reads, 0)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
        try await waitUntil { await state.listCalls > calls }
        await state.setMonitorBatches([[state.monitor]])
        try await waitUntil { controller.nextSyncAt != nil }
        XCTAssertEqual(controller.lastSentBrightness, 50)
    }

    func testInternalDisplayOnlySkipsBackgroundDDCButSyncNowStillProbes() async throws {
        let state = AutoLoopFakeState(monitors: [])
        let controller = makeController(state: state, hasOnlineExternalDisplay: { false })
        controller.disconnectedRetryInterval = .milliseconds(30)
        await controller.start()
        defer { controller.stop() }
        try await Task.sleep(for: .milliseconds(120))
        let calls = await state.listCalls
        let reads = await state.luxReads
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(reads, 0)
        await state.setMonitorBatches([[state.monitor]])
        controller.applyNow()
        try await waitUntil { controller.nextSyncAt != nil }
        XCTAssertEqual(controller.lastSentBrightness, 50)
    }

    func testAutoOffDiscardsInFlightLuxAndResumesWithFreshReading() async throws {
        let state = AutoLoopFakeState()
        await state.holdNextLux()
        let controller = makeController(state: state)
        await controller.start()
        defer { controller.stop() }
        try await waitUntil { await state.pendingLux != nil }

        controller.toggleAuto()
        await state.releaseLux(500)
        try await Task.sleep(for: .milliseconds(1100))
        let disabledReads = await state.luxReads
        let disabledWrites = await state.writes
        XCTAssertEqual(disabledReads, 1)
        XCTAssertTrue(disabledWrites.isEmpty)
        XCTAssertEqual(controller.currentLux, 0)
        XCTAssertNil(controller.nextSyncAt)

        controller.resumeAuto()
        try await waitUntil { controller.nextSyncAt != nil }
        let resumedReads = await state.luxReads
        let resumedWrites = await state.writes
        XCTAssertEqual(resumedReads, 2)
        XCTAssertEqual(resumedWrites.count, 1)
        XCTAssertEqual(controller.currentLux, 44)
    }

    func testPauseSleepAndRepeatedStartDoNotCreateExtraWork() async throws {
        let state = AutoLoopFakeState()
        let controller = makeController(state: state)
        controller.isPaused = true
        await controller.start()
        await controller.start()
        defer { controller.stop() }
        let discoveries = await state.listCalls
        XCTAssertEqual(discoveries, 1)

        try await Task.sleep(for: .milliseconds(1100))
        let pausedReads = await state.luxReads
        XCTAssertEqual(pausedReads, 0)

        controller.togglePause()
        try await waitUntil { controller.nextSyncAt != nil }
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
        XCTAssertNil(controller.nextSyncAt)
        try await Task.sleep(for: .milliseconds(1100))
        let sleepingReads = await state.luxReads
        XCTAssertEqual(sleepingReads, 1)

        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
        try await waitUntil { controller.nextSyncAt != nil }
        let resumedReads = await state.luxReads
        XCTAssertEqual(resumedReads, 2)
    }
}
