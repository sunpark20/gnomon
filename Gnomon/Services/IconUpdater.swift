//
//  IconUpdater.swift
//  Gnomon
//
//  Drives dock icon + menu bar icon.
//  Uses a 1-minute tick so the shadow interpolates smoothly and survives
//  sleep/wake gaps that would otherwise desync an hourly scheduledTimer.
//  Also re-renders immediately on wake.
//

import AppKit
import Foundation

@MainActor
public final class IconUpdater {
    private var minuteTimer: Timer?
    private var autoEnabledObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    public var currentAutoEnabled = true

    public weak var statusItem: NSStatusItem?

    /// Calendar pinned to Asia/Seoul per user request. Localize properly if the
    /// app ever ships outside Korea — see TODO in PRD.
    private let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
        return cal
    }()

    public func start() {
        refreshNow()
        scheduleMinuteTicks()
        autoEnabledObserver = NotificationCenter.default.addObserver(
            forName: .gnomonAutoStateChanged,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let extracted = (note.userInfo?["enabled"] as? Bool) ?? true
            Task { @MainActor in
                self?.currentAutoEnabled = extracted
                self?.refreshNow()
            }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshNow()
                self?.scheduleMinuteTicks()
            }
        }
    }

    public func stop() {
        minuteTimer?.invalidate()
        minuteTimer = nil
        if let observer = autoEnabledObserver {
            NotificationCenter.default.removeObserver(observer)
            autoEnabledObserver = nil
        }
        if let observer = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            wakeObserver = nil
        }
    }

    public func refreshNow() {
        let components = calendar.dateComponents([.hour, .minute], from: Date())
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        updateMenuBarIcon(hour: hour, minute: minute)
    }

    private func scheduleMinuteTicks() {
        minuteTimer?.invalidate()
        let now = Date()
        let nextMinute = calendar.nextDate(
            after: now,
            matching: DateComponents(second: 1),
            matchingPolicy: .nextTime
        ) ?? now.addingTimeInterval(60)
        let delay = nextMinute.timeIntervalSince(now)

        minuteTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.refreshNow()
                self?.scheduleRepeatingMinute()
            }
        }
    }

    private func scheduleRepeatingMinute() {
        minuteTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshNow()
            }
        }
    }

    private func updateMenuBarIcon(hour: Int, minute: Int) {
        guard let button = statusItem?.button else { return }
        let style: SundialIconRenderer.Style = currentAutoEnabled ? .menuBarActive : .menuBarInactive
        let image = SundialIconRenderer.image(hour: hour, minute: minute, style: style)
        image.size = NSSize(width: 18, height: 18)
        button.image = image
    }
}
