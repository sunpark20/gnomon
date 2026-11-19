//
//  AutoLoopControllerTests.swift
//  GnomonTests
//

import XCTest
@testable import Gnomon

private enum AutoLoopFakeError: Error {
    case writeFailed
}

private let autoLoopTestMonitor = MonitorID(slot: 1, displayName: "Test Display", uuid: "123")

actor AutoLoopFakeState {
    nonisolated let monitor = autoLoopTestMonitor
    var lux: Double = 44
    var luxReads = 0
    var pendingLux: CheckedContinuation<Double, Never>?
    var shouldHoldLux = false
    var monitors: [MonitorID]
    var brightness: Int
    var contrast = 70
    var writes: [Int] = []
    var listCalls = 0
    var failedWritesRemaining = 0
    var failedBrightnessReadsRemaining = 0
    var ignoredWritesRemaining = 0
    var monitorBatches: [[MonitorID]] = []
    var logEntries: [CSVLogEntry] = []

    init(monitors: [MonitorID]? = nil, brightness: Int = 50) {
        self.monitors = monitors ?? [autoLoopTestMonitor]
        self.brightness = brightness
    }

    func currentLux() async -> Double {
        luxReads += 1
        if shouldHoldLux {
            shouldHoldLux = false
            return await withCheckedContinuation { pendingLux = $0 }
        }
        return lux
    }

    func holdNextLux() {
        shouldHoldLux = true
    }

    func releaseLux(_ reading: Double) {
        pendingLux?.resume(returning: reading)
        pendingLux = nil
    }

    func listDisplays() -> [MonitorID] {
        listCalls += 1
        if !monitorBatches.isEmpty {
            return monitorBatches.removeFirst()
        }
        return monitors
    }

    func getBrightness(on monitor: MonitorID) throws -> Int {
        if failedBrightnessReadsRemaining > 0 {
            failedBrightnessReadsRemaining -= 1
            throw M1DDCClient.ClientError.ddcReadFailed
        }
        return brightness
    }

    func setBrightness(_ value: Int, on monitor: MonitorID) throws {
        if failedWritesRemaining > 0 {
            failedWritesRemaining -= 1
            throw AutoLoopFakeError.writeFailed
        }
        writes.append(value)
        if ignoredWritesRemaining > 0 {
            ignoredWritesRemaining -= 1
            return
        }
        brightness = value
    }

    func getContrast(on monitor: MonitorID) -> Int {
        contrast
    }

    func setContrast(_ value: Int, on monitor: MonitorID) {
        contrast = value
    }

    func appendLog(_ entry: CSVLogEntry) {
        logEntries.append(entry)
    }

    func setHardwareBrightness(_ value: Int) {
        brightness = value
    }

    func clearWrites() {
        writes.removeAll()
    }

    func setFailedWritesRemaining(_ count: Int) {
        failedWritesRemaining = count
    }

    func failNextBrightnessReads(_ count: Int) {
        failedBrightnessReadsRemaining = count
    }

    func setIgnoredWritesRemaining(_ count: Int) {
        ignoredWritesRemaining = count
    }

    func setMonitorBatches(_ batches: [[MonitorID]]) {
        monitorBatches = batches
    }
}

@MainActor
final class AutoLoopControllerTests: XCTestCase {
    func makeController(
        state: AutoLoopFakeState = AutoLoopFakeState(),
        hasOnlineExternalDisplay: @escaping @Sendable () -> Bool = { true }
    ) -> AutoLoopController {
        let controller = AutoLoopController(dependencies: AutoLoopDependencies(
            currentLux: {
                await state.currentLux()
            },
            hasOnlineExternalDisplay: hasOnlineExternalDisplay,
            listDisplays: {
                await state.listDisplays()
            },
            getBrightness: { monitor in
                try await state.getBrightness(on: monitor)
            },
            setBrightness: { value, monitor in
                try await state.setBrightness(value, on: monitor)
            },
            getContrast: { monitor in
                await state.getContrast(on: monitor)
            },
            setContrast: { value, monitor in
                await state.setContrast(value, on: monitor)
            },
            ensureLogFile: {},
            rotateLog: {},
            writeDiagnostics: { _ in },
            appendLog: { entry in
                await state.appendLog(entry)
            }
        ))
        controller.brightnessVerificationDelay = .zero
        return controller
    }

    func waitUntil(
        _ condition: () async -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while await !condition() {
            guard ContinuousClock.now < deadline else {
                XCTFail("Timed out waiting for controller", file: file, line: line)
                throw AutoLoopFakeError.writeFailed
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    func testUserSetBrightnessDisablesAuto() {
        let controller = AutoLoopController()
        XCTAssertTrue(controller.autoEnabled, "Default state should be Auto on")
        controller.userSetBrightness(50)
        XCTAssertFalse(controller.autoEnabled, "Manual slider interaction must disable Auto")
        XCTAssertEqual(controller.lastSentBrightness, 50)
        XCTAssertEqual(controller.targetBrightness, 50)
        XCTAssertNotNil(controller.manualOverrideAt)
    }

    func testToggleAutoFlipsFlag() {
        let controller = AutoLoopController()
        XCTAssertTrue(controller.autoEnabled)
        controller.toggleAuto()
        XCTAssertFalse(controller.autoEnabled)
        controller.toggleAuto()
        XCTAssertTrue(controller.autoEnabled)
    }

    func testResumeAutoClearsManualOverride() {
        let controller = AutoLoopController()
        controller.userSetBrightness(40)
        XCTAssertNotNil(controller.manualOverrideAt)
        controller.resumeAuto()
        XCTAssertTrue(controller.autoEnabled)
        XCTAssertNil(controller.manualOverrideAt)
    }

    func testUserSetBrightnessClampsOutOfRange() {
        let controller = AutoLoopController()
        controller.userSetBrightness(-10)
        XCTAssertEqual(controller.lastSentBrightness, 0)
        controller.userSetBrightness(150)
        XCTAssertEqual(controller.lastSentBrightness, 100)
    }

    func testTogglePause() {
        let controller = AutoLoopController()
        XCTAssertFalse(controller.isPaused)
        controller.togglePause()
        XCTAssertTrue(controller.isPaused)
        controller.togglePause()
        XCTAssertFalse(controller.isPaused)
    }

    func testAutoOnForcesWriteEvenWhenCachedBrightnessMatchesTarget() async throws {
        let state = AutoLoopFakeState(brightness: 50)
        let controller = makeController(state: state)
        await controller.start()
        defer { controller.stop() }
        try await waitUntil { controller.nextSyncAt != nil }
        await state.clearWrites()

        controller.toggleAuto()
        controller.toggleAuto()
        try await Task.sleep(for: .milliseconds(100))

        let writes = await state.writes
        XCTAssertEqual(writes, [50])
        XCTAssertEqual(controller.lastSentBrightness, 50)
    }

    func testDisplayRecoveryForcesWriteForSameMonitorUUID() async throws {
        let state = AutoLoopFakeState(brightness: 50)
        let controller = makeController(state: state)
        await controller.start()
        defer { controller.stop() }
        try await waitUntil { controller.nextSyncAt != nil }
        controller.displayRecoveryDelays = [.zero]
        await state.clearWrites()

        controller.startDisplayRecovery(reason: "test")
        try await Task.sleep(for: .milliseconds(100))

        let writes = await state.writes
        XCTAssertEqual(writes, [50])
        XCTAssertEqual(controller.lastSentBrightness, 50)
    }

    func testFailedForcedWriteInvalidatesCachedBrightness() async throws {
        let state = AutoLoopFakeState(brightness: 50)
        let controller = makeController(state: state)
        await controller.start()
        defer { controller.stop() }
        try await waitUntil { controller.nextSyncAt != nil }
        await state.clearWrites()
        await state.setFailedWritesRemaining(2)

        controller.applyNow()
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertNil(controller.lastSentBrightness)

        controller.applyNow()
        try await Task.sleep(for: .milliseconds(100))

        let writes = await state.writes
        XCTAssertEqual(writes, [50])
        XCTAssertEqual(controller.lastSentBrightness, 50)
    }

    func testSilentWriteNoOpRetriesAfterReadBackMismatch() async throws {
        let state = AutoLoopFakeState(brightness: 85)
        let controller = makeController(state: state)
        await controller.start()
        defer { controller.stop() }
        try await waitUntil { controller.nextSyncAt != nil }
        await state.clearWrites()
        await state.setHardwareBrightness(85)
        await state.setIgnoredWritesRemaining(1)

        controller.applyNow()
        try await Task.sleep(for: .milliseconds(100))

        let writes = await state.writes
        let brightness = await state.brightness
        XCTAssertEqual(writes, [50, 50])
        XCTAssertEqual(brightness, 50)
        XCTAssertEqual(controller.lastSentBrightness, 50)
        XCTAssertNotNil(controller.activeMonitor)
    }

    func testRepeatedSilentWriteNoOpMarksMonitorDisconnected() async throws {
        let state = AutoLoopFakeState(brightness: 85)
        let controller = makeController(state: state)
        await controller.start()
        defer { controller.stop() }
        try await waitUntil { controller.nextSyncAt != nil }
        await state.clearWrites()
        await state.setHardwareBrightness(85)
        await state.setIgnoredWritesRemaining(2)

        controller.applyNow()
        try await Task.sleep(for: .milliseconds(100))

        let writes = await state.writes
        XCTAssertEqual(writes, [50, 50])
        XCTAssertNil(controller.lastSentBrightness)
        XCTAssertNil(controller.activeMonitor)
        XCTAssertFalse(controller.monitorConnected)
    }

    func testDisplayRecoveryRetriesUntilMonitorIsAvailable() async throws {
        let state = AutoLoopFakeState(monitors: [], brightness: 50)
        let controller = makeController(state: state)
        controller.displayRecoveryDelays = [.zero, .milliseconds(50)]
        await controller.start()
        defer { controller.stop() }
        await state.setMonitorBatches([[], [state.monitor]])

        controller.startDisplayRecovery(reason: "test")
        try await Task.sleep(for: .milliseconds(150))

        let writes = await state.writes
        XCTAssertEqual(writes, [50])
        XCTAssertEqual(controller.activeMonitor?.uuid, "123")
    }

    func testDisplayRecoveryRetriesWhenDDCIsEnumeratedButNotReady() async throws {
        let state = AutoLoopFakeState()
        let controller = makeController(state: state)
        await controller.start()
        defer { controller.stop() }
        try await waitUntil { controller.nextSyncAt != nil }
        await state.clearWrites()
        await state.setFailedWritesRemaining(2)

        controller.displayRecoveryDelays = [.zero, .milliseconds(25)]
        controller.startDisplayRecovery(reason: "test")
        try await waitUntil { controller.nextSyncAt != nil }
        let writes = await state.writes
        XCTAssertEqual(writes, [controller.targetBrightness])
        XCTAssertTrue(controller.monitorConnected)
    }

    func testDisplayRecoveryDoesNotWriteWhenAutoIsDisabled() async throws {
        let state = AutoLoopFakeState(brightness: 50)
        let controller = makeController(state: state)
        await controller.start()
        defer { controller.stop() }
        try await waitUntil { controller.nextSyncAt != nil }
        controller.toggleAuto()
        let originalReads = await state.luxReads
        controller.displayRecoveryDelays = [.zero]
        await state.clearWrites()

        controller.startDisplayRecovery(reason: "test")
        try await Task.sleep(for: .milliseconds(100))

        let writes = await state.writes
        XCTAssertTrue(writes.isEmpty)
        let reads = await state.luxReads
        XCTAssertEqual(reads, originalReads)
    }
}
