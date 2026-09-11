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

    private func present() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        let window = window ?? makeWindow()
        self.window = window
        window.delegate = self

        window.level = .normal
        window.collectionBehavior = [.moveToActiveSpace]
        if !window.setFrameUsingName("SageDashboardWindow") {
            window.setFrame(AppState.cascadeCenteredFrame(for: window), display: false)
        }
        window.sageFadeInForPresentation()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        // Environments must wrap `.sageAccessibilityObservation()` — that modifier
        // reads `@Environment(AccessibilitySettings.self)` from ancestors, not content.
        let root = DashboardView()
            .sageScaledTypography()
            .sageAccessibilityObservation()
            .environment(appState)
            .environment(AccessibilitySettings.shared)
        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Dashboard"
        window.identifier = NSUserInterfaceItemIdentifier(AppState.WindowIdentifier.dashboard)
        window.titleVisibility = .visible
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.sageApplyLiquidGlass(customTitlebar: false)
        window.hasShadow = true
        // Log rows are text-selectable; background drags would fight selection.
        window.isMovableByWindowBackground = false
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.minSize = NSSize(width: 360, height: 360)
        window.setContentSize(NSSize(width: 420, height: 520))
        window.setFrameAutosaveName("SageDashboardWindow")
        return window
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        AppState.demoteToAccessoryIfNeeded(
            excluding: notification.object as? NSWindow
        )
    }
}
