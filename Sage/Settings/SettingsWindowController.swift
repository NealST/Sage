//
//  SettingsWindowController.swift
//  Sage
//

import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let appState: AppState
    private var window: NSWindow?
    private lazy var skillsController = SkillsManageWindowController(appState: appState)

    init(appState: AppState) {
        self.appState = appState
        super.init()
    }

    func show() {
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

        // Normal level: yields to other apps when Sage is inactive.
        window.level = .normal
        window.collectionBehavior = [.moveToActiveSpace]
        if !window.setFrameUsingName("SageSettingsWindow") {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        // Environments must wrap `.sageAccessibilityObservation()` — that modifier
        // reads `@Environment(AccessibilitySettings.self)` from ancestors, not content.
        let root = SettingsView(
            settings: appState.settings,
            onDone: { [weak self] in self?.window?.performClose(nil) },
            onOpenSkills: { [weak self] session in
                self?.showSkills(pinnedSession: session)
            }
        )
            .sageScaledTypography()
            .sageAccessibilityObservation()
            .environment(appState)
            .environment(AccessibilitySettings.shared)
        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Settings"
        // Titlebar chrome stays; only the title label is hidden so traffic lights sit normally.
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = false
        window.styleMask = [.titled, .closable]
        window.isOpaque = true
        window.backgroundColor = .windowBackgroundColor
        window.hasShadow = true
        // Keep false so field/text drag selects content instead of moving the window.
        window.isMovableByWindowBackground = false
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.setContentSize(NSSize(width: 440, height: 620))
        window.setFrameAutosaveName("SageSettingsWindow")
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        return window
    }

    func windowWillClose(_ notification: Notification) {
        let otherOpen = NSApp.windows.contains { window in
            (window.title == "Sage" || window.title == "Skills" || window.title == "Dashboard") && window.isVisible
        }
        if !otherOpen {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        // Ensure we never stick above other apps after losing focus.
        window?.level = .normal
    }
}
