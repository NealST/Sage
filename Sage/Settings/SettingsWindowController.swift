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

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let appState: AppState
    private var window: NSWindow?
    private lazy var skillsController = SkillsManageWindowController(appState: appState)
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

    func showSkills(pinnedSession: AgentSession) {
        skillsController.show(pinnedSession: pinnedSession)
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
            onOpenSkills: { [weak self] session in
                self?.showSkills(pinnedSession: session)
            },
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
        window.minSize = NSSize(width: 680, height: 480)
        window.setContentSize(NSSize(width: 720, height: 640))
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
