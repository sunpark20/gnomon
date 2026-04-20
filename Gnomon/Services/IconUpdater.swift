//
//  IconUpdater.swift
//  Gnomon
//
//  Hourly tick driving the dock icon and menu bar icon renderings.
//

import AppKit
import Foundation

@MainActor
public final class IconUpdater {
    private var hourTimer: Timer?
    private var autoEnabledObserver: NSObjectProtocol?
    public var currentAutoEnabled = true

    public weak var statusItem: NSStatusItem?

    public func start() {
        refreshNow()
        scheduleHourly()
        autoEnabledObserver = NotificationCenter.default.addObserver(
            forName: .gnomonAutoStateChanged,
            object: nil,
            queue: .main
        ) { [weak self] note in
            // Extract Sendable data before hopping to MainActor.
            let extracted = (note.userInfo?["enabled"] as? Bool) ?? true
            Task { @MainActor in
                self?.currentAutoEnabled = extracted
                self?.refreshNow()
            }
        }
    }

    public func stop() {
        hourTimer?.invalidate()
        hourTimer = nil
        if let observer = autoEnabledObserver {
            NotificationCenter.default.removeObserver(observer)
            autoEnabledObserver = nil
        }
    }

    public func refreshNow() {
        let hour = Calendar.current.component(.hour, from: Date())
        updateDockIcon(hour: hour)
        updateMenuBarIcon(hour: hour)
    }

    private func scheduleHourly() {
        hourTimer?.invalidate()
        let now = Date()
        let calendar = Calendar.current
        let nextHour = calendar.nextDate(
            after: now,
            matching: DateComponents(minute: 0, second: 1),
            matchingPolicy: .nextTime
        ) ?? now.addingTimeInterval(3600)
        let delay = nextHour.timeIntervalSince(now)

        // Wait for next hour boundary, then fire every 3600s.
        hourTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.refreshNow()
                self?.scheduleHourlyRepeating()
            }
        }
    }

    private func scheduleHourlyRepeating() {
        hourTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshNow()
            }
        }
    }

    private func updateDockIcon(hour: Int) {
        let image = SundialIconRenderer.image(hour: hour, style: .dock)
        NSApp.applicationIconImage = image
    }

    private func updateMenuBarIcon(hour: Int) {
        guard let button = statusItem?.button else { return }
        let style: SundialIconRenderer.Style = currentAutoEnabled ? .menuBarActive : .menuBarInactive
        let image = SundialIconRenderer.image(hour: hour, style: style)
        image.size = NSSize(width: 18, height: 18)
        button.image = image
    }
}
