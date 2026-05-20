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

private actor AutoLoopFakeState {
    nonisolated let monitor = autoLoopTestMonitor
    var lux: Double = 44
    var monitors: [MonitorID]
    var brightness: Int
    var contrast = 70
    var writes: [Int] = []
    var listCalls = 0
    var failedWritesRemaining = 0
    var monitorBatches: [[MonitorID]] = []
    var logEntries: [CSVLogEntry] = []

    init(monitors: [MonitorID]? = nil, brightness: Int = 50) {
        self.monitors = monitors ?? [autoLoopTestMonitor]
        self.brightness = brightness
    }

    func currentLux() -> Double {
        lux
    }

    func listDisplays() -> [MonitorID] {
        listCalls += 1
        if !monitorBatches.isEmpty {
            return monitorBatches.removeFirst()
        }
        return monitors
    }

    func getBrightness(on monitor: MonitorID) -> Int {
        brightness
    }

    func setBrightness(_ value: Int, on monitor: MonitorID) throws {
        if failedWritesRemaining > 0 {
            failedWritesRemaining -= 1
            throw AutoLoopFakeError.writeFailed
        }
        brightness = value
        writes.append(value)
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

    func clearWrites() {
        writes.removeAll()
    }

    func setFailedWritesRemaining(_ count: Int) {
        failedWritesRemaining = count
    }

    func setMonitorBatches(_ batches: [[MonitorID]]) {
        monitorBatches = batches
    }
}

@MainActor
final class AutoLoopControllerTests: XCTestCase {
    private func makeController(
        state: AutoLoopFakeState = AutoLoopFakeState()
    ) -> AutoLoopController {
        AutoLoopController(dependencies: AutoLoopDependencies(
            currentLux: {
                await state.currentLux()
            },
            listDisplays: {
                await state.listDisplays()
            },
            getBrightness: { monitor in
                await state.getBrightness(on: monitor)
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
        controller.stop()
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
        controller.stop()
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
        controller.stop()
        await state.clearWrites()
        await state.setFailedWritesRemaining(1)

        controller.applyNow()
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertNil(controller.lastSentBrightness)

        controller.applyNow()
        try await Task.sleep(for: .milliseconds(100))

        let writes = await state.writes
        XCTAssertEqual(writes, [50])
        XCTAssertEqual(controller.lastSentBrightness, 50)
    }

    func testDisplayRecoveryRetriesUntilMonitorIsAvailable() async throws {
        let state = AutoLoopFakeState(monitors: [], brightness: 50)
        let controller = makeController(state: state)
        controller.displayRecoveryDelays = [.zero, .milliseconds(50)]
        await state.setMonitorBatches([[], [state.monitor]])

        controller.startDisplayRecovery(reason: "test")
        try await Task.sleep(for: .milliseconds(150))

        let writes = await state.writes
        XCTAssertEqual(writes, [50])
        XCTAssertEqual(controller.activeMonitor?.uuid, "123")
    }

    func testDisplayRecoveryDoesNotWriteWhenAutoIsDisabled() async throws {
        let state = AutoLoopFakeState(brightness: 50)
        let controller = makeController(state: state)
        await controller.start()
        controller.stop()
        controller.toggleAuto()
        controller.displayRecoveryDelays = [.zero]
        await state.clearWrites()

        controller.startDisplayRecovery(reason: "test")
        try await Task.sleep(for: .milliseconds(100))

        let writes = await state.writes
        XCTAssertTrue(writes.isEmpty)
    }
}
