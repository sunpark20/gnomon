//
//  M1DDCClientTests.swift
//  GnomonTests
//

import XCTest
@testable import Gnomon

/// Integration tests that talk to the real hardware.
/// Guarded by GNOMON_INTEGRATION=1 so CI and casual test runs don't need a monitor.
final class M1DDCClientIntegrationTests: XCTestCase {
    private var shouldRun: Bool {
        ProcessInfo.processInfo.environment["GNOMON_INTEGRATION"] == "1"
    }

    func testListDisplaysReturnsSomething() async throws {
        try XCTSkipUnless(shouldRun, "Set GNOMON_INTEGRATION=1 to run hardware tests")
        let client = M1DDCClient()
        let displays = try await client.listDisplays()
        XCTAssertGreaterThan(displays.count, 0, "Expected at least one display")
    }

    func testBrightnessRoundTrip() async throws {
        try XCTSkipUnless(shouldRun, "Set GNOMON_INTEGRATION=1 to run hardware tests")
        let client = M1DDCClient()
        let displays = try await client.listDisplays()
        guard let target = displays.first(where: { !$0.uuid.isEmpty }) else {
            XCTFail("No usable display found")
            return
        }

        let original = try await client.getBrightness(on: target)
        let probe = original >= 50 ? 30 : 70
        try await client.setBrightness(probe, on: target)

        // Give the monitor a moment to commit.
        try await Task.sleep(for: .milliseconds(300))
        let readBack = try await client.getBrightness(on: target)
        XCTAssertEqual(readBack, probe, "Monitor did not accept brightness change")

        // Restore.
        try await client.setBrightness(original, on: target)
    }
}
