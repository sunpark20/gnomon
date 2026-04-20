//
//  StatusBarController.swift
//  Gnomon
//
//  Menu-bar icon. Left-click toggles the window, right-click shows a menu.
//

import AppKit
import Foundation

@MainActor
public final class StatusBarController {
    private let statusItem: NSStatusItem
    private var rightClickMenu: NSMenu?

    public init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        configureButton()
        buildMenu()
    }

    public var rawItem: NSStatusItem {
        statusItem
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        // Initial placeholder — IconUpdater will render the real sundial.
        let image = NSImage(systemSymbolName: "sun.max.fill", accessibilityDescription: "Gnomon")
        image?.isTemplate = true
        button.image = image
        button.target = StatusBarProxy.shared
        button.action = #selector(StatusBarProxy.handleClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func buildMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Show Window", action: #selector(StatusBarProxy.showWindow), keyEquivalent: "")
            .target = StatusBarProxy.shared
        menu.addItem(.separator())
        menu.addItem(withTitle: "About Gnomon", action: #selector(StatusBarProxy.showAbout), keyEquivalent: "")
            .target = StatusBarProxy.shared
        menu.addItem(.separator())
        let quit = menu.addItem(
            withTitle: "Quit Gnomon",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quit.target = NSApp
        rightClickMenu = menu
    }

    public func popUpMenu() {
        guard let menu = rightClickMenu, let button = statusItem.button else { return }
        menu.popUp(positioning: nil, at: .zero, in: button)
    }
}

/// NSStatusItem needs an Objective-C target. We route selectors through this
/// shared proxy and then call back into Swift-native code.
@MainActor
public final class StatusBarProxy: NSObject {
    public static let shared = StatusBarProxy()

    public var onLeftClick: (() -> Void)?
    public var onShowAbout: (() -> Void)?
    public weak var statusBarController: StatusBarController?

    override private init() {
        super.init()
    }

    @objc public func handleClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            onLeftClick?()
            return
        }
        if event.type == .rightMouseUp {
            statusBarController?.popUpMenu()
        } else {
            onLeftClick?()
        }
    }

    @objc public func showWindow() {
        onLeftClick?()
    }

    @objc public func showAbout() {
        onShowAbout?()
        NSApp.orderFrontStandardAboutPanel(nil)
    }
}
