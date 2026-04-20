//
//  M1DDCClientTests.swift
//  GnomonTests
//

import XCTest
@testable import Gnomon

final class M1DDCClientParseTests: XCTestCase {
    func testParseSingleDisplay() {
        let input = "[1] LG HDR 4K (57E749D2-BBF2-4931-8EBC-6B9A3D4FF8A2)"
        let monitors = M1DDCClient.parseDisplayList(input)
        XCTAssertEqual(monitors.count, 1)
        XCTAssertEqual(monitors[0].slot, 1)
        XCTAssertEqual(monitors[0].displayName, "LG HDR 4K")
        XCTAssertEqual(monitors[0].uuid, "57E749D2-BBF2-4931-8EBC-6B9A3D4FF8A2")
    }

    func testParseMultiDisplay() {
        let input = """
        [1] LG HDR 4K (57E749D2-BBF2-4931-8EBC-6B9A3D4FF8A2)
        [2] (null) (37D8832A-2D66-02CA-B9F7-8F30A301B230)
        """
        let monitors = M1DDCClient.parseDisplayList(input)
        XCTAssertEqual(monitors.count, 2)
        XCTAssertEqual(monitors[1].slot, 2)
        XCTAssertEqual(monitors[1].displayName, "(null)")
        XCTAssertEqual(monitors[1].uuid, "37D8832A-2D66-02CA-B9F7-8F30A301B230")
    }

    func testParseEmptyInput() {
        XCTAssertTrue(M1DDCClient.parseDisplayList("").isEmpty)
    }

    func testParseMalformedLine() {
        let input = "not a valid line\n[1] LG HDR 4K (UUID-HERE)\ngarbage\n"
        let monitors = M1DDCClient.parseDisplayList(input)
        XCTAssertEqual(monitors.count, 1)
        XCTAssertEqual(monitors[0].displayName, "LG HDR 4K")
    }
}

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
