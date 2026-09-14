//
//  SettingsWindowController.swift
//  Sage
//

import AppKit
import SwiftUI

/// Deep-link into a specific Settings pane, optionally raising a sheet.
@MainActor
struct SettingsPresentationRequest {
    var pane: SettingsPane?
    var openMCPManage: Bool
}

/// Window dimensions shared by the NSWindow chrome and the SwiftUI content,
/// so the hosted view's minimums can't drift from the window's minSize.
enum SettingsWindowMetrics {
    static let minWidth: CGFloat = 680
    static let minHeight: CGFloat = 480
    static let defaultWidth: CGFloat = 720
    static let defaultHeight: CGFloat = 640
}

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let appState: AppState
    private var window: NSWindow?
    /// Delivered to the (recreated) SettingsView when the window is presented.
    private var pendingPresentation: SettingsPresentationRequest?

    init(appState: AppState) {
        self.appState = appState
        super.init()
    }

    func show(pane: SettingsPane? = nil, openMCPManage: Bool = false) {
        if pane != nil || openMCPManage {
            pendingPresentation = SettingsPresentationRequest(
                pane: pane,
                openMCPManage: openMCPManage
            )
        }
        // MenuBarExtra actions need a turn of the run loop before a window can key.
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
        if let request = pendingPresentation {
            pendingPresentation = nil
            settingsPresentationHandler?(request)
        }

        // Normal level: yields to other apps when Sage is inactive.
        window.level = .normal
        window.collectionBehavior = [.moveToActiveSpace]
        if !window.setFrameUsingName("SageSettingsWindow.sidebar") {
            window.setFrame(AppState.cascadeCenteredFrame(for: window), display: false)
        }
        window.sageFadeInForPresentation()
        window.makeKeyAndOrderFront(nil)
    }

    /// Set by the hosted SettingsView so a deep-link request (e.g. the
    /// Dashboard's MCP empty state) lands after the view is on screen.
    var settingsPresentationHandler: ((SettingsPresentationRequest) -> Void)?

    private func makeWindow() -> NSWindow {
        // Environments must wrap `.sageAccessibilityObservation()` — that modifier
        // reads `@Environment(AccessibilitySettings.self)` from ancestors, not content.
        let root = SettingsView(
            settings: appState.settings,
            onPresentationRequest: { [weak self] handler in
                self?.settingsPresentationHandler = handler
            }
        )
            .sageScaledTypography()
            .sageAccessibilityObservation()
            .environment(appState)
            .environment(AccessibilitySettings.shared)
        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Settings"
        window.identifier = NSUserInterfaceItemIdentifier(AppState.WindowIdentifier.settings)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.sageApplyLiquidGlass(customTitlebar: false)
        window.hasShadow = true
        // Keep false so field/text drag selects content instead of moving the window.
        window.isMovableByWindowBackground = false
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.minSize = NSSize(
            width: SettingsWindowMetrics.minWidth,
            height: SettingsWindowMetrics.minHeight
        )
        window.setContentSize(NSSize(
            width: SettingsWindowMetrics.defaultWidth,
            height: SettingsWindowMetrics.defaultHeight
        ))
        window.setFrameAutosaveName("SageSettingsWindow.sidebar")
        return window
    }

    func windowWillClose(_ notification: Notification) {
        AppState.demoteToAccessoryIfNeeded(
            excluding: notification.object as? NSWindow
        )
    }

    func windowDidResignKey(_ notification: Notification) {
        // Ensure we never stick above other apps after losing focus.
        window?.level = .normal
    }
}
