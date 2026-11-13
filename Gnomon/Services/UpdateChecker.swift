//
//  UpdateChecker.swift
//  Gnomon
//
//  Sparkle updater integration. Sparkle handles signed feed checks, download
//  verification, installation, and relaunch. The existing preference key is
//  kept so users' automatic-check setting survives the updater change.
//

import AppKit
import Combine
import Foundation
import Sparkle

@MainActor
public final class UpdateChecker: ObservableObject {
    public static let shared = UpdateChecker()

    public static let disabledKey = "updateCheckDisabled"
    public static let skippedVersionKey = "updateSkippedVersion"
    private static let scheduledCheckInterval: TimeInterval = 24 * 60 * 60

    @Published public private(set) var statusMessage: String?
    @Published public private(set) var isBusy = false

    private let defaults: UserDefaults
    private var updaterController: SPUStandardUpdaterController?
    private var defaultsObserver: NSObjectProtocol?
    private var updaterStarted = false

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [Self.disabledKey: false])

        if Self.hasValidUpdaterConfiguration {
            let controller = SPUStandardUpdaterController(
                startingUpdater: false,
                updaterDelegate: nil,
                userDriverDelegate: nil
            )
            controller.updater.updateCheckInterval = Self.scheduledCheckInterval
            controller.updater.automaticallyChecksForUpdates = !defaults.bool(forKey: Self.disabledKey)
            updaterController = controller
        }

        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: defaults,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                setAutomaticChecksEnabled(!self.defaults.bool(forKey: Self.disabledKey))
            }
        }
    }

    private static var hasValidUpdaterConfiguration: Bool {
        #if DEBUG
        return false
        #else
        guard
            let feedString = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
            let feedURL = URL(string: feedString),
            feedURL.scheme == "https",
            let publicKey = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
            Data(base64Encoded: publicKey)?.count == 32 else
        {
            return false
        }
        return true
        #endif
    }

    // MARK: - Public entry points

    /// Starts Sparkle's scheduled checks. Sparkle handles the daily interval;
    /// this does not force an immediate update check on every launch.
    public func checkOnLaunch() async {
        guard let updaterController else { return }
        updaterController.updater.automaticallyChecksForUpdates = !defaults.bool(forKey: Self.disabledKey)
        updaterController.startUpdater()
        updaterStarted = true
    }

    /// Opens Sparkle's native update checker and installation flow.
    public func checkManually() async {
        guard let updaterController else {
            statusMessage = "Updates are available in installed release builds."
            return
        }

        isBusy = true
        defer { isBusy = false }
        statusMessage = nil
        startUpdaterIfNeeded()
        updaterController.checkForUpdates(nil)
    }

    private func setAutomaticChecksEnabled(_ enabled: Bool) {
        updaterController?.updater.automaticallyChecksForUpdates = enabled
    }

    private func startUpdaterIfNeeded() {
        guard !updaterStarted else { return }
        updaterController?.startUpdater()
        updaterStarted = updaterController != nil
    }

    // MARK: - Version comparison

    /// Numeric segment-wise comparison, tolerant of a leading "v" ("1.10" > "1.9").
    public nonisolated static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        let lhs = numericSegments(of: candidate)
        let rhs = numericSegments(of: current)
        let count = max(lhs.count, rhs.count)
        for i in 0 ..< count {
            let l = i < lhs.count ? lhs[i] : 0
            let r = i < rhs.count ? rhs[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    private nonisolated static func numericSegments(of version: String) -> [Int] {
        var trimmed = version.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("v") || trimmed.hasPrefix("V") {
            trimmed = String(trimmed.dropFirst())
        }
        return trimmed.split(separator: ".").map { Int($0.prefix(while: \.isNumber)) ?? 0 }
    }
}
