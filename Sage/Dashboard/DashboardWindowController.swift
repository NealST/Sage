//
//  DashboardWindowController.swift
//  Sage
//
//  Manages the Dashboard window lifecycle — similar to SettingsWindowController.
//

import AppKit
import SwiftUI

@MainActor
final class DashboardWindowController: NSObject, NSWindowDelegate {
    private let appState: AppState
    private var window: NSWindow?

    init(appState: AppState) {
        self.appState = appState
        super.init()
    }

    func show() {
        DispatchQueue.main.async { [weak self] in
            self?.present()
        }
    }

    func toggle() {
        if let window, window.isVisible {
            if window.isKeyWindow {
                window.orderOut(nil)
            } else {
                focus(window)
            }
        } else {
            show()
        }
    }

    private func present() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        let window = window ?? makeWindow()
        self.window = window
        window.delegate = self

        window.level = .normal
        window.collectionBehavior = [.moveToActiveSpace]
        if !window.setFrameUsingName("SageDashboardWindow") {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
    }

    private func focus(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let root = DashboardView()
            .environment(appState)
        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Dashboard"
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isOpaque = true
        window.backgroundColor = .windowBackgroundColor
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.minSize = NSSize(width: 360, height: 300)
        window.setContentSize(NSSize(width: 400, height: 420))
        window.setFrameAutosaveName("SageDashboardWindow")
        return window
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        let otherOpen = NSApp.windows.contains {
            ($0.title == "Sage" || $0.title == "Settings") && $0.isVisible
        }
        if !otherOpen {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
