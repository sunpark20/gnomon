//
//  StatusBarController.swift
//  Gnomon
//
//  Menu-bar icon. Left-click toggles the window, right-click shows a menu.
//

import AppKit
import Foundation

@MainActor
public final class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private var rightClickMenu: NSMenu?

    override public init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
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
        menu.delegate = self
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

    /// AppKit의 정식 status-item 메뉴 경로를 태워 띄운다.
    /// `menu.popUp(...)`을 버튼 action 내부에서 직접 호출하면
    /// 첫 팝업 시 scroll chevron이 잠깐 보이는 글리치가 생긴다.
    public func popUpMenu() {
        guard let menu = rightClickMenu, let button = statusItem.button else { return }
        statusItem.menu = menu
        button.performClick(nil)
    }

    /// 메뉴가 닫히면 menu 연결을 풀어 좌클릭이 다시 button action으로 간다.
    public func menuDidClose(_ menu: NSMenu) {
        statusItem.menu = nil
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
