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
public final class AutoLoopController {
    // MARK: - Public state (UI bindings)

    public private(set) var currentLux: Double = 0
    public private(set) var emaLux: Double = 0
    public private(set) var targetBrightness = 50
    public private(set) var lastSentBrightness: Int?
    public private(set) var lastSyncAt: Date?
    public private(set) var nextSyncAt: Date?
    public private(set) var activeMonitor: MonitorID?

    public var autoEnabled = true
    public var isPaused = false
    public var parameters: BrightnessCurve.Parameters = .default
    public var syncInterval: TimeInterval = 30

    // MARK: - Dependencies

    private let luxReader: LuxReader
    private let ddcClient: M1DDCClient

    // MARK: - Private state

    private var ema = EMAFilter(alpha: 0.2)
    private var sampleTask: Task<Void, Never>?
    private var syncTask: Task<Void, Never>?
    private let deadband = 2 // PRD §5.3
    private let sampleInterval: TimeInterval = 1.0

    // MARK: - Init

    public init(
        luxReader: LuxReader = LuxReader(),
        ddcClient: M1DDCClient = M1DDCClient()
    ) {
        self.luxReader = luxReader
        self.ddcClient = ddcClient
    }

    // MARK: - Lifecycle

    public func start() async {
        do {
            let monitors = try await ddcClient.listDisplays()
            activeMonitor = monitors.first(where: { !$0.uuid.isEmpty })
            if let monitor = activeMonitor {
                lastSentBrightness = try? await ddcClient.getBrightness(on: monitor)
            }
        } catch {
            print("[AutoLoop] start: discovery failed: \(error.localizedDescription)")
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
            }
        } catch {
            // Swallow transient read errors — UI keeps last good value.
            print("[AutoLoop] sample error: \(error.localizedDescription)")
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
        } catch {
            print("[sync] DDC error: \(error.localizedDescription)")
        }
    }
}
