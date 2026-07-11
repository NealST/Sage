//
//  SettingsWindowController.swift
//  Sage
//

import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let settings: ModelSettings
    private var window: NSWindow?

    init(settings: ModelSettings) {
        self.settings = settings
        super.init()
    }

    func show() {
        // MenuBarExtra actions need a turn of the run loop before a window can key.
        DispatchQueue.main.async { [weak self] in
            self?.present()
        }
    }

    private func present() {
        // Accessory apps often fail to surface .normal windows; go regular briefly.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        let window = window ?? makeWindow()
        self.window = window
        window.delegate = self

        if window.screen == nil {
            window.center()
        }
        window.level = .floating
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private func makeWindow() -> NSWindow {
        let root = SettingsView(settings: settings) { [weak self] in
            self?.window?.performClose(nil)
        }
        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Sage Settings"
        window.styleMask = [.titled, .closable]
        window.titlebarAppearsTransparent = false
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 460, height: 280))
        window.center()
        return window
    }

    func windowWillClose(_ notification: Notification) {
        // Return to menu-bar agent mode (no Dock icon).
        NSApp.setActivationPolicy(.accessory)
    }
}
