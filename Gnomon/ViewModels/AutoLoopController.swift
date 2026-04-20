//
//  AutoLoopController.swift
//  Gnomon
//
//  Central state hub. Samples lux every second (UI freshness),
//  sends DDC brightness every sync interval (default 30s, PRD §5.3),
//  applies deadband + EMA smoothing to avoid flicker.
//

import Foundation
import Observation

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

    private let luxReader: LuxReader
    private let ddcClient: M1DDCClient
    private let logger: CSVLogger

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

    // MARK: - Init

    public init(
        luxReader: LuxReader = LuxReader(),
        ddcClient: M1DDCClient = M1DDCClient(),
        logger: CSVLogger = CSVLogger()
    ) {
        self.luxReader = luxReader
        self.ddcClient = ddcClient
        self.logger = logger
    }

    // MARK: - Lifecycle

    public func start() async {
        // Pull persisted user preferences BEFORE the sync loop starts,
        // so saved values (interval, bMin/bMax) take effect immediately
        // rather than waiting for the user to reopen Settings.
        loadPersistedPreferences()

        do {
            let monitors = try await ddcClient.listDisplays()
            activeMonitor = monitors.first(where: { !$0.uuid.isEmpty })
            if let monitor = activeMonitor {
                lastSentBrightness = try? await ddcClient.getBrightness(on: monitor)
                // m1ddc occasionally returns 0 when the read transiently fails;
                // 0 is also a nonsensical usable contrast. Treat it as "no reading"
                // and keep the factory default (70) rather than stamping 0 over it.
                if let existingContrast = try? await ddcClient.getContrast(on: monitor),
                   existingContrast > 0
                {
                    contrast = existingContrast
                }
            }
        } catch {
            print("[AutoLoop] start: discovery failed: \(error.localizedDescription)")
        }

        // Prune old log rows + write system diagnostics once at startup.
        // Ignore errors — logging is non-critical.
        let displayNames = await (try? ddcClient.listDisplays())?.map {
            "\($0.displayName) [\($0.uuid)]"
        } ?? []
        let info = SystemInfo.collect(activeDisplays: displayNames)
        Task.detached { [logger] in
            // ensureFile first: upgrades the header if the schema changed and
            // backs up the old file, so rotate operates on the current schema.
            try? await logger.ensureFile()
            try? await logger.rotate()
            try? await logger.writeDiagnostics(info)
        }

        nextSyncAt = Date().addingTimeInterval(syncInterval)
        scheduleSampling()
        scheduleSyncing()
    }

    public func stop() {
        sampleTask?.cancel()
        syncTask?.cancel()
        sampleTask = nil
        syncTask = nil
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

    // MARK: - Sampling (fast loop, UI only)

    private func scheduleSampling() {
        sampleTask?.cancel()
        sampleTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.sampleOnce()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func sampleOnce() async {
        do {
            let raw = try await luxReader.currentLux()
            currentLux = raw
            emaLux = ema.update(raw)
            if autoEnabled, !isPaused {
                targetBrightness = BrightnessCurve.target(lux: emaLux, parameters: parameters)
                // A snap means a sustained genuine scene change (covered sensor,
                // lights off). Bypass the interval cadence and push immediately
                // so the user sees a quick response even at long sync intervals.
                // Modest EMA-tracked drift still waits for the normal sync tick.
                if ema.didSnapOnLastUpdate {
                    await snapSyncImmediately()
                }
            }
        } catch {
            // Swallow transient read errors — UI keeps last good value.
            print("[AutoLoop] sample error: \(error.localizedDescription)")
        }
    }

    private func snapSyncImmediately() async {
        guard let monitor = activeMonitor else { return }
        let target = targetBrightness
        let last = lastSentBrightness ?? -9999
        guard abs(target - last) >= deadband else { return }
        do {
            try await ddcClient.setBrightness(target, on: monitor)
            lastSentBrightness = target
            lastSyncAt = Date()
            print("[snap-sync] ema=\(Int(emaLux)) target=\(target) (bypassed interval)")
            await logEntry(sentBrightness: target, manualOverride: false)
            // Reset the sync cadence so we don't double-write immediately after.
            syncTask?.cancel()
            updateNextSyncAt()
            scheduleSyncing()
        } catch {
            print("[snap-sync] DDC error: \(error.localizedDescription)")
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
        guard autoEnabled, !isPaused, let monitor = activeMonitor else { return }
        let target = targetBrightness
        let last = lastSentBrightness ?? -9999

        guard abs(target - last) >= deadband else {
            print("[sync] skip (delta < deadband): target=\(target) last=\(last)")
            return
        }

        do {
            try await ddcClient.setBrightness(target, on: monitor)
            lastSentBrightness = target
            lastSyncAt = Date()
            print("[sync] lux=\(Int(currentLux)) ema=\(Int(emaLux)) target=\(target) sent=\(target)")
            await logEntry(sentBrightness: target, manualOverride: false)
        } catch {
            print("[sync] DDC error: \(error.localizedDescription)")
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
        try? await logger.append(entry)
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
        let client = ddcClient
        manualWriteDebouncer.schedule { [weak self] in
            do {
                try await client.setBrightness(clamped, on: monitor)
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
    }

    /// Toggles Auto on/off.
    public func toggleAuto() {
        autoEnabled.toggle()
        if autoEnabled { manualOverrideAt = nil }
    }

    /// Writes the current computed target immediately, ignoring the deadband.
    public func applyNow() {
        guard let monitor = activeMonitor else { return }
        let target = targetBrightness
        let client = ddcClient
        Task { [weak self] in
            do {
                try await client.setBrightness(target, on: monitor)
                self?.lastSentBrightness = target
                self?.lastSyncAt = Date()
            } catch {
                print("[applyNow] DDC error: \(error.localizedDescription)")
            }
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
        let client = ddcClient
        contrastWriteDebouncer.schedule {
            do {
                try await client.setContrast(clamped, on: monitor)
            } catch {
                print("[contrast] DDC error: \(error.localizedDescription)")
            }
        }
    }
}
