//
//  AutoLoopController.swift
//  Gnomon
//
//  Central state hub. Samples lux every second (UI freshness),
//  sends DDC brightness every sync interval (default 30s, PRD §5.3),
//  applies deadband + EMA smoothing to avoid flicker.
//

import AppKit
import Foundation
import Observation

private enum AutoLoopWriteError: LocalizedError {
    case brightnessVerificationFailed(expected: Int, actual: Int)

    var errorDescription: String? {
        switch self {
        case let .brightnessVerificationFailed(expected, actual):
            "DDC brightness verification failed: expected \(expected), read back \(actual)"
        }
    }
}

// swiftlint:disable file_length
@MainActor
@Observable
// swiftlint:disable:next type_body_length
public final class AutoLoopController {
    // MARK: - Public state (UI bindings)

    public private(set) var currentLux: Double = 0
    public private(set) var emaLux: Double = 0
    public private(set) var targetBrightness = 50
    public private(set) var lastSentBrightness: Int?
    public private(set) var lastSyncAt: Date?
    public private(set) var nextSyncAt: Date?
    public private(set) var activeMonitor: MonitorID?

    public var autoEnabled = true {
        didSet {
            if autoEnabled != oldValue {
                if autoEnabled {
                    manualOverrideAt = nil
                    manualWriteDebouncer.cancel()
                }
                reconcileAutomaticWork()

                NotificationCenter.default.post(
                    name: .gnomonAutoStateChanged,
                    object: nil,
                    userInfo: ["enabled": autoEnabled]
                )
            }
        }
    }

    public var isPaused = false {
        didSet {
            if isPaused != oldValue { reconcileAutomaticWork() }
        }
    }

    public var parameters: BrightnessCurve.Parameters = .default
    public var syncInterval: TimeInterval = 30

    // MARK: - Dependencies

    private let dependencies: AutoLoopDependencies

    // MARK: - Private state

    // Snap: |sample − value| ≥ 50 lux for 3 consecutive 1s samples bypasses EMA.
    // Catches covered-sensor / lights-off scenes in ~3s while ignoring blips.
    private var ema = EMAFilter(alpha: 0.2, snapThreshold: 50, snapDuration: 3)
    private var sampleTask: Task<Void, Never>?
    private var syncTask: Task<Void, Never>?
    private let deadband = 2 // PRD §5.3
    private let sampleInterval: TimeInterval = 1.0
    private let manualWriteDebouncer = Debouncer(delay: .milliseconds(200))
    private let contrastWriteDebouncer = Debouncer(delay: .milliseconds(200))
    public private(set) var manualOverrideAt: Date?
    public var contrast = 70 // PRD §5.2.2 fixed default (LG factory)
    public var monitorConnected: Bool {
        activeMonitor != nil
    }

    private var isRunning = false
    private var didFinishStartup = false
    private var runGeneration = 0
    private var systemSleeping = false
    private var screensSleeping = false
    private var recoveringDisplay = false
    private var remainingRecoveryDelays: ArraySlice<Duration>?
    private var displayObservers: [(NotificationCenter, NSObjectProtocol)] = []
    private var displayRecoveryTask: Task<Void, Never>?
    private var applyTask: Task<Void, Never>?
    private var diagnosticsTask: Task<Void, Never>?
    private var brightnessWriteInProgress = false

    private var canDiscoverDisplays: Bool {
        isRunning && !systemSleeping && !screensSleeping
    }

    private var automaticWorkEnabled: Bool {
        canDiscoverDisplays && didFinishStartup && !recoveringDisplay && autoEnabled && !isPaused
    }

    private var canRunAutomaticWork: Bool {
        automaticWorkEnabled && activeMonitor != nil
    }

    var displayRecoveryDelays: [Duration] = [.zero, .seconds(3), .seconds(8), .seconds(20), .seconds(60)]
    var disconnectedRetryInterval: Duration = .seconds(60)
    var brightnessVerificationDelay: Duration = .milliseconds(120)
    private let rediscoveryDebouncer = Debouncer(delay: .seconds(2))

    // MARK: - Init

    public init(
        luxReader: LuxReader = LuxReader(),
        ddcClient: M1DDCClient = M1DDCClient(),
        logger: CSVLogger = CSVLogger()
    ) {
        dependencies = .live(luxReader: luxReader, ddcClient: ddcClient, logger: logger)
    }

    init(dependencies: AutoLoopDependencies) {
        self.dependencies = dependencies
    }

    // MARK: - Lifecycle

    public func start() async {
        guard !isRunning, !Task.isCancelled else { return }
        isRunning = true
        runGeneration += 1
        let generation = runGeneration
        loadPersistedPreferences()
        installDisplayObservers()
        let monitors = await (try? dependencies.listDisplays()) ?? []
        guard isRunning, generation == runGeneration else { return }
        if canDiscoverDisplays, !recoveringDisplay, activeMonitor == nil,
           let monitor = pickMonitor(from: monitors)
        {
            let brightness = try? await dependencies.getBrightness(monitor)
            guard isRunning, generation == runGeneration else { return }
            let existingContrast = canDiscoverDisplays ? try? await dependencies.getContrast(monitor) : nil
            guard isRunning, generation == runGeneration else { return }
            if canDiscoverDisplays, !recoveringDisplay, activeMonitor == nil {
                activeMonitor = monitor
                if manualOverrideAt == nil { lastSentBrightness = brightness }
                if let existingContrast, existingContrast > 0 { contrast = existingContrast }
            }
        }

        let displayNames = monitors.map { "\($0.displayName) [\($0.uuid)]" }
        let info = SystemInfo.collect(activeDisplays: displayNames)
        diagnosticsTask = Task.detached { [dependencies] in
            guard !Task.isCancelled else { return }
            try? await dependencies.ensureLogFile()
            guard !Task.isCancelled else { return }
            try? await dependencies.rotateLog()
            guard !Task.isCancelled else { return }
            try? await dependencies.writeDiagnostics(info)
        }
        didFinishStartup = true
        reconcileAutomaticWork()
    }

    public func stop() {
        isRunning = false
        didFinishStartup = false
        stopAutomaticWork()
        cancelDisplayRecovery()
        diagnosticsTask?.cancel()
        diagnosticsTask = nil
        manualWriteDebouncer.cancel()
        contrastWriteDebouncer.cancel()
        activeMonitor = nil
        systemSleeping = false
        screensSleeping = false
        for (center, observer) in displayObservers {
            center.removeObserver(observer)
        }
        displayObservers.removeAll()
    }

    /// Reads UserDefaults values that Settings writes via @AppStorage and
    /// applies them to the controller. Called on every launch so the user's
    /// saved interval / range actually takes effect without opening Settings.
    private func loadPersistedPreferences() {
        let defaults = UserDefaults.standard

        if defaults.object(forKey: "syncIntervalSeconds") != nil {
            let stored = defaults.double(forKey: "syncIntervalSeconds")
            if stored > 0 { syncInterval = stored }
        }

        let storedMin = defaults.object(forKey: "brightnessMin") as? Int
        let storedMax = defaults.object(forKey: "brightnessMax") as? Int
        let storedFloor = defaults.object(forKey: "darkFloorLux") as? Double
        if let minValue = storedMin, let maxValue = storedMax, minValue < maxValue {
            parameters = BrightnessCurve.Parameters(
                minBrightness: minValue,
                maxBrightness: maxValue,
                luxCeiling: parameters.luxCeiling,
                darkFloorLux: storedFloor ?? parameters.darkFloorLux
            )
        } else if let floor = storedFloor {
            parameters = BrightnessCurve.Parameters(
                minBrightness: parameters.minBrightness,
                maxBrightness: parameters.maxBrightness,
                luxCeiling: parameters.luxCeiling,
                darkFloorLux: floor
            )
        }
    }

    private func pickMonitor(from monitors: [MonitorID]) -> MonitorID? {
        monitors.first(where: { !$0.uuid.isEmpty })
    }

    // MARK: - Display observers

    private func installDisplayObservers() {
        let center = NSWorkspace.shared.notificationCenter
        observe(NSWorkspace.willSleepNotification, in: center) {
            $0.systemSleeping = true
            $0.suspendForSleep()
        }
        observe(NSWorkspace.screensDidSleepNotification, in: center) {
            $0.screensSleeping = true
            $0.suspendForSleep()
        }
        observe(NSWorkspace.didWakeNotification, in: center) {
            $0.systemSleeping = false
            $0.scheduleDisplayRecovery(reason: "wake")
        }
        observe(NSWorkspace.screensDidWakeNotification, in: center) {
            $0.screensSleeping = false
            $0.scheduleDisplayRecovery(reason: "screen-wake")
        }
        observe(NSApplication.didChangeScreenParametersNotification, in: .default) {
            $0.scheduleDisplayRecovery(reason: "screen-change")
        }
    }

    private func observe(
        _ name: Notification.Name,
        in center: NotificationCenter,
        action: @escaping @MainActor @Sendable (AutoLoopController) -> Void
    ) {
        let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let controller = self, controller.isRunning else { return }
                action(controller)
            }
        }
        displayObservers.append((center, observer))
    }

    private func suspendForSleep() {
        stopAutomaticWork()
        cancelDisplayRecovery()
        manualWriteDebouncer.cancel()
        contrastWriteDebouncer.cancel()
    }

    private func scheduleDisplayRecovery(reason: String) {
        guard canDiscoverDisplays else { return }
        cancelDisplayRecovery()
        recoveringDisplay = true
        stopAutomaticWork()
        rediscoveryDebouncer.schedule { [weak self] in
            self?.startDisplayRecovery(reason: reason)
        }
    }

    private func cancelDisplayRecovery() {
        rediscoveryDebouncer.cancel()
        displayRecoveryTask?.cancel()
        displayRecoveryTask = nil
        recoveringDisplay = false
        remainingRecoveryDelays = nil
    }

    private func rediscoverMonitor() async -> MonitorID? {
        guard !Task.isCancelled, canDiscoverDisplays else { return nil }
        let monitors = await (try? dependencies.listDisplays()) ?? []
        guard !Task.isCancelled, canDiscoverDisplays else { return nil }
        activeMonitor = pickMonitor(from: monitors)
        return activeMonitor
    }

    func startDisplayRecovery(reason: String) {
        guard canDiscoverDisplays else { return }
        remainingRecoveryDelays = displayRecoveryDelays[...]
        runDisplayRecovery(reason: reason)
    }

    private func runDisplayRecovery(reason: String) {
        displayRecoveryTask?.cancel()
        recoveringDisplay = true
        stopAutomaticWork()
        displayRecoveryTask = Task { [weak self] in
            await self?.recoverDisplay(reason: reason)
        }
    }

    private func recoverDisplay(reason: String) async {
        while let delay = remainingRecoveryDelays?.popFirst() {
            if delay > .zero { try? await Task.sleep(for: delay) }
            guard !Task.isCancelled else { return }
            let monitor = await rediscoverMonitor()
            guard !Task.isCancelled else { return }
            if monitor != nil { break }
        }
        recoveringDisplay = false
        displayRecoveryTask = nil
        if activeMonitor == nil || !autoEnabled || isPaused {
            remainingRecoveryDelays = nil
        }
        reconcileAutomaticWork(reason: reason)
    }

    private func monitorForWrite(reason: String) async -> MonitorID? {
        if let activeMonitor {
            return activeMonitor
        }
        print("[\(reason)] no active DDC monitor, rediscovering…")
        return await rediscoverMonitor()
    }

    private func markMonitorUnhealthy(reason: String) {
        if let monitor = activeMonitor {
            print("[ddc] marking monitor unhealthy (\(monitor.displayName)): \(reason)")
        }
        activeMonitor = nil
        lastSentBrightness = nil
        if remainingRecoveryDelays?.isEmpty == false {
            runDisplayRecovery(reason: "ddc-recovery")
        } else {
            reconcileAutomaticWork()
        }
    }

    private func writeBrightnessAndVerify(_ target: Int, on monitor: MonitorID) async throws {
        try Task.checkCancellation()
        try await dependencies.setBrightness(target, monitor)
        try Task.checkCancellation()
        if brightnessVerificationDelay > .zero {
            try await Task.sleep(for: brightnessVerificationDelay)
        }
        let actual: Int
        do {
            actual = try await dependencies.getBrightness(monitor)
        } catch M1DDCClient.ClientError.ddcReadFailed {
            // The write may have succeeded even if the monitor missed the read request.
            try await Task.sleep(for: brightnessVerificationDelay)
            actual = try await dependencies.getBrightness(monitor)
        }
        try Task.checkCancellation()
        guard abs(actual - target) <= 1 else {
            throw AutoLoopWriteError.brightnessVerificationFailed(expected: target, actual: actual)
        }
    }

    private func writeBrightnessWithRetry(_ target: Int, on monitor: MonitorID) async throws {
        do {
            try await writeBrightnessAndVerify(target, on: monitor)
        } catch let error as CancellationError {
            throw error
        } catch {
            try Task.checkCancellation()
            let firstError = error
            print("[ddc-retry] first write/verify failed, rediscovering…")
            if let fresh = await rediscoverMonitor() {
                do {
                    try await writeBrightnessAndVerify(target, on: fresh)
                } catch let error as CancellationError {
                    throw error
                } catch {
                    try Task.checkCancellation()
                    markMonitorUnhealthy(reason: error.localizedDescription)
                    throw error
                }
            } else {
                try Task.checkCancellation()
                markMonitorUnhealthy(reason: firstError.localizedDescription)
                throw firstError
            }
        }
    }

    // MARK: - Automatic work

    private func stopAutomaticWork() {
        sampleTask?.cancel()
        syncTask?.cancel()
        applyTask?.cancel()
        sampleTask = nil
        syncTask = nil
        applyTask = nil
        nextSyncAt = nil
    }

    private func reconcileAutomaticWork(reason: String = "auto-resume") {
        guard canRunAutomaticWork else {
            if !recoveringDisplay { remainingRecoveryDelays = nil }
            stopAutomaticWork()
            if automaticWorkEnabled { scheduleDisconnectedRetry() }
            return
        }
        guard sampleTask == nil else { return }
        ema.reset()
        sampleTask = Task { [weak self, sampleInterval] in
            while !Task.isCancelled {
                await self?.sampleOnce(reason: reason)
                if self == nil { return }
                try? await Task.sleep(for: .seconds(sampleInterval), tolerance: .milliseconds(100))
            }
        }
    }

    /// While disconnected, the sync task only checks for a returning monitor.
    /// Sleep, display changes and Sync Now cancel it through stopAutomaticWork().
    private func scheduleDisconnectedRetry() {
        syncTask = Task { [weak self, disconnectedRetryInterval] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: disconnectedRetryInterval)
                } catch {
                    return
                }
                guard let self, automaticWorkEnabled, activeMonitor == nil else { return }
                guard dependencies.hasOnlineExternalDisplay() else { continue }
                if await rediscoverMonitor() != nil {
                    reconcileAutomaticWork(reason: "reconnect")
                    return
                }
            }
        }
    }

    private func sampleOnce(reason: String) async {
        guard canRunAutomaticWork, !Task.isCancelled else { return }
        let isFirstSample = ema.value == nil
        do {
            let raw = try await dependencies.currentLux()
            guard !Task.isCancelled, canRunAutomaticWork else { return }
            currentLux = raw
            emaLux = ema.update(raw)
            targetBrightness = BrightnessCurve.target(lux: emaLux, parameters: parameters)
        } catch {
            return
        }

        if isFirstSample || ema.didSnapOnLastUpdate {
            let didSync = await syncCurrentTarget(force: isFirstSample, reason: isFirstSample ? reason : "snap-sync")
            guard !Task.isCancelled, isFirstSample || didSync else { return }
            if isFirstSample, didSync { remainingRecoveryDelays = nil }
            scheduleSyncing()
        }
    }

    private func scheduleSyncing() {
        syncTask?.cancel()
        guard canRunAutomaticWork, ema.value != nil else { return }
        updateNextSyncAt()
        syncTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let interval = self?.syncInterval else { return }
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { return }
                _ = await self?.syncCurrentTarget(force: false, reason: "sync")
                guard !Task.isCancelled else { return }
                self?.updateNextSyncAt()
            }
        }
    }

    private func updateNextSyncAt() {
        nextSyncAt = Date().addingTimeInterval(syncInterval)
    }

    private func waitForBrightnessWrite() async throws {
        while brightnessWriteInProgress {
            try await Task.sleep(for: .milliseconds(25))
        }
        try Task.checkCancellation()
    }

    @discardableResult
    private func syncCurrentTarget(force: Bool, reason: String) async -> Bool {
        if force {
            do {
                try await waitForBrightnessWrite()
            } catch {
                return false
            }
        }
        guard canRunAutomaticWork, ema.value != nil, !Task.isCancelled,
              !brightnessWriteInProgress, let monitor = activeMonitor else { return false }
        let decision = SyncDecision.evaluate(SyncDecision.Input(
            autoEnabled: autoEnabled,
            isPaused: isPaused,
            force: force,
            target: targetBrightness,
            lastSent: lastSentBrightness,
            deadband: deadband
        ))
        guard case let .write(target) = decision else { return false }

        brightnessWriteInProgress = true
        defer { brightnessWriteInProgress = false }
        do {
            try await writeBrightnessWithRetry(target, on: monitor)
            try Task.checkCancellation()
            lastSentBrightness = target
            lastSyncAt = Date()
            let mode = force ? "forced" : "normal"
            print("[\(reason)] \(mode) lux=\(Int(currentLux)) ema=\(Int(emaLux)) target=\(target) sent=\(target)")
            await logEntry(sentBrightness: target, manualOverride: false)
            return true
        } catch is CancellationError {
            return false
        } catch {
            lastSentBrightness = nil
            print("[\(reason)] DDC error (after retry): \(error.localizedDescription)")
            return false
        }
    }

    private func logEntry(sentBrightness: Int, manualOverride: Bool) async {
        let entry = CSVLogEntry(
            rawLux: currentLux,
            emaLux: emaLux,
            targetBrightness: targetBrightness,
            sentBrightness: sentBrightness,
            contrast: contrast,
            autoOn: autoEnabled,
            manualOverride: manualOverride,
            bMin: parameters.minBrightness,
            bMax: parameters.maxBrightness
        )
        try? await dependencies.appendLog(entry)
    }

    // MARK: - User interactions (Phase 4)

    /// Called when the user drags a brightness slider or enters a value.
    /// Turns Auto off and schedules a debounced DDC write.
    public func userSetBrightness(_ value: Int) {
        let clamped = max(0, min(100, value))
        autoEnabled = false
        manualOverrideAt = Date()
        lastSentBrightness = clamped
        targetBrightness = clamped
        manualWriteDebouncer.schedule { [weak self] in
            guard let self, canDiscoverDisplays else { return }
            guard let monitor = await monitorForWrite(reason: "manual") else {
                guard !Task.isCancelled else { return }
                lastSentBrightness = nil
                return
            }
            do {
                try await waitForBrightnessWrite()
                brightnessWriteInProgress = true
                defer { brightnessWriteInProgress = false }
                try await writeBrightnessWithRetry(clamped, on: monitor)
                try Task.checkCancellation()
                lastSentBrightness = clamped
                lastSyncAt = Date()
                await logEntry(sentBrightness: clamped, manualOverride: true)
            } catch is CancellationError {
                return
            } catch {
                lastSentBrightness = nil
                print("[manual] DDC error: \(error.localizedDescription)")
            }
        }
    }

    /// Re-enables Auto after the user adjusts brightness manually.
    public func resumeAuto() {
        autoEnabled = true
    }

    public func toggleAuto() {
        autoEnabled.toggle()
    }

    /// Writes the current computed target immediately, ignoring the deadband.
    public func applyNow() {
        guard canDiscoverDisplays, didFinishStartup, autoEnabled, !isPaused, !recoveringDisplay else { return }
        if activeMonitor == nil {
            startDisplayRecovery(reason: "apply-now")
            return
        }
        applyTask?.cancel()
        applyTask = Task { [weak self] in
            _ = await self?.syncCurrentTarget(force: true, reason: "apply-now")
        }
    }

    /// Toggles the pause state. Pause stops both DDC writes and target recomputation.
    public func togglePause() {
        isPaused.toggle()
    }

    /// Called when the user changes sync interval in Settings.
    /// Applies the current target immediately so they see feedback right away,
    /// then restarts the sync timer so the next cycle respects the new cadence.
    public func intervalDidChange() {
        applyNow()
        scheduleSyncing()
    }

    /// Manual contrast change (PRD §5.2.2 — not driven by ambient light).
    public func userSetContrast(_ value: Int) {
        let clamped = max(0, min(100, value))
        contrast = clamped
        contrastWriteDebouncer.schedule { [weak self] in
            guard let self, canDiscoverDisplays else { return }
            guard let monitor = await monitorForWrite(reason: "contrast"), !Task.isCancelled else { return }
            do {
                try await dependencies.setContrast(clamped, monitor)
                guard !Task.isCancelled else { return }
                reconcileAutomaticWork()
            } catch {
                guard !Task.isCancelled else { return }
                markMonitorUnhealthy(reason: error.localizedDescription)
                print("[contrast] DDC error: \(error.localizedDescription)")
            }
        }
    }
}
