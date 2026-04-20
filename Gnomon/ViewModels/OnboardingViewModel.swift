//
//  OnboardingViewModel.swift
//  Gnomon
//
//  Runs the initial diagnostic checklist (PRD §5.9):
//    1. lux sensor available
//    2. DDC-addressable external monitor detected
//    3. Color-temp notice (informational)
//

import AppKit
import Foundation
import Observation

@MainActor
@Observable
public final class OnboardingViewModel {
    public enum CheckState: Sendable, Equatable {
        case pending
        case running
        case passed(detail: String)
        case failed(detail: String)
    }

    public var luxState: CheckState = .pending
    public var ddcState: CheckState = .pending

    private let luxReader: LuxReader
    private let ddcClient: M1DDCClient

    public init(luxReader: LuxReader = LuxReader(), ddcClient: M1DDCClient = M1DDCClient()) {
        self.luxReader = luxReader
        self.ddcClient = ddcClient
    }

    public var allPassed: Bool {
        [luxState, ddcState].allSatisfy {
            if case .passed = $0 { return true }
            return false
        }
    }

    public func runAll() async {
        await runLuxCheck()
        await runDDCCheck()
    }

    public func runLuxCheck() async {
        luxState = .running
        do {
            let lux = try await luxReader.currentLux()
            luxState = .passed(detail: String(format: "Ambient sensor OK (%.0f lx)", lux))
        } catch {
            luxState = .failed(detail: "macOS auto-brightness must be enabled in System Settings → Displays")
        }
    }

    public func runDDCCheck() async {
        ddcState = .running
        do {
            let monitors = try await ddcClient.listDisplays()
            let external = monitors.filter { !$0.uuid.isEmpty }
            if external.isEmpty {
                ddcState = .failed(detail: "No DDC-addressable external monitor found")
            } else {
                let name = external.first?.displayName ?? "external monitor"
                ddcState = .passed(detail: "Detected: \(name)")
            }
        } catch {
            ddcState = .failed(detail: "DDC error: \(error.localizedDescription)")
        }
    }

    public func openLunarWarningIfNeeded() -> String? {
        let lunar = NSWorkspace.shared.runningApplications.first { app in
            app.bundleIdentifier == "com.alin23.Lunar"
        }
        return lunar != nil ? "Lunar is running. Please quit it to avoid DDC conflicts." : nil
    }
}
