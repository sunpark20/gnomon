import AppKit
import SwiftUI
import XCTest
@testable import Gnomon

@MainActor
final class WindowVisibilityTests: XCTestCase {
    func testVisibilityFollowsTheWindow() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["GNOMON_INTEGRATION"] == "1",
            "Requires a visible macOS desktop"
        )
        let window = NSPanel(
            contentRect: NSRect(x: 80, y: 80, width: 80, height: 80),
            styleMask: [.titled, .nonactivatingPanel, .miniaturizable],
            backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.level = .floating
        defer { window.close() }

        var visible = false
        window.contentView = NSHostingView(rootView: WindowVisibilityReader(isVisible: Binding(
            get: { visible }, set: { visible = $0 }
        )))
        for _ in 0 ..< 2 {
            window.orderFrontRegardless()
            try await waitForVisibility { visible }
            window.orderOut(nil)
            try await waitForVisibility { !visible }
        }

        window.orderFrontRegardless()
        try await waitForVisibility { visible }
        window.miniaturize(nil)
        try await waitForVisibility { !visible }
        window.deminiaturize(nil)
        try await waitForVisibility { visible }

        NSApp.hide(nil)
        defer { NSApp.unhideWithoutActivation() }
        try await waitForVisibility { !visible }
        NSApp.unhideWithoutActivation()
        try await waitForVisibility { visible }

        let cover = makeCover(above: window)
        defer { cover.close() }
        cover.setFrame(window.frame.insetBy(dx: -4, dy: -4), display: false)
        cover.orderFrontRegardless()
        try await waitForVisibility { !visible }
        cover.setFrameOrigin(.init(x: window.frame.midX, y: window.frame.minY))
        try await waitForVisibility { visible }
    }

    private func makeCover(above window: NSWindow) -> NSPanel {
        let cover = NSPanel(
            contentRect: window.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        cover.isReleasedWhenClosed = false
        cover.hidesOnDeactivate = false
        cover.isOpaque = true
        cover.backgroundColor = .windowBackgroundColor
        cover.level = .init(rawValue: window.level.rawValue + 1)
        return cover
    }

    private func waitForVisibility(_ matches: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while !matches(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(matches())
    }
}
