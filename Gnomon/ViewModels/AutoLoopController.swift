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
                NotificationCenter.default.post(
                    name: .gnomonAutoStateChanged,
                    object: nil,
                    userInfo: ["enabled": autoEnabled]
                )
            }
        }
    }

    public var isPaused = false
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

    private var wakeObserver: (any NSObjectProtocol)?
    private var screenObserver: (any NSObjectProtocol)?
    private var initialSyncTask: Task<Void, Never>?
    private var displayRecoveryTask: Task<Void, Never>?
    var displayRecoveryDelays: [Duration] = [.zero, .seconds(3), .seconds(5)]
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
        // Pull persisted user preferences BEFORE the sync loop starts,
        // so saved values (interval, bMin/bMax) take effect immediately
        // rather than waiting for the user to reopen Settings.
        loadPersistedPreferences()

        var monitors: [MonitorID] = []
        do {
            monitors = try await dependencies.listDisplays()
            activeMonitor = pickMonitor(from: monitors)
            if let monitor = activeMonitor {
                lastSentBrightness = try? await dependencies.getBrightness(monitor)
                // m1ddc occasionally returns 0 when the read transiently fails;
                // 0 is also a nonsensical usable contrast. Treat it as "no reading"
                // and keep the factory default (70) rather than stamping 0 over it.
                if let existingContrast = try? await dependencies.getContrast(monitor),
                   existingContrast > 0
                {
                    contrast = existingContrast
                }
            }
        } catch {
            print("[AutoLoop] start: discovery failed: \(error.localizedDescription)")
        }

        let displayNames = monitors.map { "\($0.displayName) [\($0.uuid)]" }
        let info = SystemInfo.collect(activeDisplays: displayNames)
        Task.detached { [dependencies] in
            // ensureFile first: upgrades the header if the schema changed and
            // backs up the old file, so rotate operates on the current schema.
            try? await dependencies.ensureLogFile()
            try? await dependencies.rotateLog()
            try? await dependencies.writeDiagnostics(info)
        }

        nextSyncAt = Date().addingTimeInterval(syncInterval)
        scheduleSampling()
        scheduleSyncing()
        installDisplayObservers()

        initialSyncTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            await self?.syncIfNeeded()
        }
    }

    public func stop() {
        sampleTask?.cancel()
        syncTask?.cancel()
        initialSyncTask?.cancel()
        displayRecoveryTask?.cancel()
        rediscoveryDebouncer.cancel()
        sampleTask = nil
        syncTask = nil
        initialSyncTask = nil
        displayRecoveryTask = nil
        removeDisplayObservers()
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
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.rediscoveryDebouncer.schedule { [weak self] in
                    self?.startDisplayRecovery(reason: "wake")
                }
            }
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.rediscoveryDebouncer.schedule { [weak self] in
                    self?.startDisplayRecovery(reason: "screen-change")
                }
            }
        }
    }

    private func removeDisplayObservers() {
        if let obs = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            wakeObserver = nil
        }
        if let obs = screenObserver {
            NotificationCenter.default.removeObserver(obs)
            screenObserver = nil
        }
    }

    @discardableResult
    private func rediscoverMonitor() async -> MonitorID? {
        let old = activeMonitor
        do {
            let monitors = try await dependencies.listDisplays()
            activeMonitor = pickMonitor(from: monitors)
        } catch {
            print("[rediscovery] listDisplays failed: \(error.localizedDescription)")
            activeMonitor = nil
        }
        if activeMonitor?.uuid != old?.uuid {
            print(
                "[rediscovery] monitor changed: \(old?.displayName ?? "nil")"
                    + " → \(activeMonitor?.displayName ?? "nil")"
            )
        }
        return activeMonitor
    }

    func startDisplayRecovery(reason: String) {
        displayRecoveryTask?.cancel()
        displayRecoveryTask = Task { [weak self] in
            guard let self else { return }
            for (index, delay) in displayRecoveryDelays.enumerated() {
                if delay > .zero {
                    try? await Task.sleep(for: delay)
                }
                if Task.isCancelled { return }
                let recovered = await recoverDisplayOnce(
                    reason: reason,
                    attempt: index + 1
                )
                if recovered { return }
            }
        }
    }

    @discardableResult
    private func recoverDisplayOnce(reason: String, attempt: Int) async -> Bool {
        guard await rediscoverMonitor() != nil else {
            print("[display-recovery] \(reason) attempt \(attempt): no DDC monitor")
            return false
        }
        await refreshLuxForSync(reason: reason)
        guard autoEnabled, !isPaused else {
            print("[display-recovery] \(reason) attempt \(attempt): auto disabled or paused")
            return true
        }
        return await syncCurrentTarget(force: true, reason: "\(reason)-recovery-\(attempt)")
    }

    private func writeBrightnessWithRetry(_ target: Int, on monitor: MonitorID) async throws {
        do {
            try await dependencies.setBrightness(target, monitor)
        } catch {
            print("[ddc-retry] first write failed, rediscovering…")
            if let fresh = await rediscoverMonitor() {
                try await dependencies.setBrightness(target, fresh)
            } else {
                throw error
            }
        }
    }

    // MARK: - Sampling (fast loop, UI only)

    private func scheduleSampling() {
        sampleTask?.cancel()
        sampleTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.sampleOnce()
                guard let interval = self?.sampleInterval else { return }
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    private func sampleOnce() async {
        do {
            try await updateLuxFromSensor()
            if ema.didSnapOnLastUpdate {
                // A snap means a sustained genuine scene change (covered sensor,
                // lights off). Bypass the interval cadence and push immediately
                // so the user sees a quick response even at long sync intervals.
                // Modest EMA-tracked drift still waits for the normal sync tick.
                await snapSyncImmediately()
            }
        } catch {
            // Swallow transient read errors — UI keeps last good value.
            print("[AutoLoop] sample error: \(error.localizedDescription)")
        }
    }

    private func updateLuxFromSensor() async throws {
        let raw = try await dependencies.currentLux()
        currentLux = raw
        emaLux = ema.update(raw)
        if autoEnabled, !isPaused {
            targetBrightness = BrightnessCurve.target(lux: emaLux, parameters: parameters)
        }
    }

    private func refreshLuxForSync(reason: String) async {
        do {
            try await updateLuxFromSensor()
        } catch {
            print("[display-recovery] \(reason): lux refresh failed: \(error.localizedDescription)")
        }
    }

    private func snapSyncImmediately() async {
        let didSync = await syncCurrentTarget(force: false, reason: "snap-sync")
        if didSync {
            syncTask?.cancel()
            scheduleSyncing()
        }
    }

    // MARK: - Syncing (slow loop, DDC)

    private func scheduleSyncing() {
        syncTask?.cancel()
        syncTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let interval = self?.syncInterval else { return }
                try? await Task.sleep(for: .seconds(interval))
                await self?.syncIfNeeded()
                self?.updateNextSyncAt()
            }
        }
    }

    private func updateNextSyncAt() {
        nextSyncAt = Date().addingTimeInterval(syncInterval)
    }

    private func syncIfNeeded() async {
        _ = await syncCurrentTarget(force: false, reason: "sync")
    }

    @discardableResult
    private func syncCurrentTarget(force: Bool, reason: String) async -> Bool {
        guard autoEnabled, !isPaused, let monitor = activeMonitor else { return false }
        let target = targetBrightness
        let last = lastSentBrightness ?? -9999

        guard force || abs(target - last) >= deadband else {
            print("[sync] skip (delta < deadband): target=\(target) last=\(last)")
            return true
        }

        do {
            try await writeBrightnessWithRetry(target, on: monitor)
            lastSentBrightness = target
            lastSyncAt = Date()
            updateNextSyncAt()
            let mode = force ? "forced" : "normal"
            print("[\(reason)] \(mode) lux=\(Int(currentLux)) ema=\(Int(emaLux)) target=\(target) sent=\(target)")
            await logEntry(sentBrightness: target, manualOverride: false)
            return true
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
        guard let monitor = activeMonitor else { return }
        manualWriteDebouncer.schedule { [weak self] in
            do {
                try await self?.writeBrightnessWithRetry(clamped, on: monitor)
                self?.lastSyncAt = Date()
                await self?.logEntry(sentBrightness: clamped, manualOverride: true)
            } catch {
                print("[manual] DDC error: \(error.localizedDescription)")
            }
        }
    }

    /// Re-enables Auto after user had nudged things manually.
    /// Next sync tick will recompute target and write if it differs.
    public func resumeAuto() {
        autoEnabled = true
        manualOverrideAt = nil
        lastSentBrightness = nil
        forceSyncAfterAutoEnabled()
    }

    /// Toggles Auto on/off.
    public func toggleAuto() {
        autoEnabled.toggle()
        if autoEnabled {
            manualOverrideAt = nil
            lastSentBrightness = nil
            forceSyncAfterAutoEnabled()
        }
    }

    private func forceSyncAfterAutoEnabled() {
        Task { [weak self] in
            guard let self else { return }
            await refreshLuxForSync(reason: "auto-on")
            await syncCurrentTarget(force: true, reason: "auto-on")
        }
    }

    /// Writes the current computed target immediately, ignoring the deadband.
    public func applyNow() {
        Task { [weak self] in
            await self?.syncCurrentTarget(force: true, reason: "apply-now")
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
        syncTask?.cancel()
        updateNextSyncAt()
        scheduleSyncing()
    }

    /// Manual contrast change (PRD §5.2.2 — not driven by ambient light).
    public func userSetContrast(_ value: Int) {
        let clamped = max(0, min(100, value))
        contrast = clamped
        guard let monitor = activeMonitor else { return }
        let dependencies = dependencies
        contrastWriteDebouncer.schedule {
            do {
                try await dependencies.setContrast(clamped, monitor)
            } catch {
                print("[contrast] DDC error: \(error.localizedDescription)")
            }
        }
    }
}
