//
//  SkillsManageWindowController.swift
//  Sage
//
//  Standalone Skills browser window — titled, closable, and draggable.
//

import AppKit
import SwiftUI

@MainActor
final class SkillsManageWindowController: NSObject, NSWindowDelegate {
    private let appState: AppState
    private var window: NSWindow?

    init(appState: AppState) {
        self.appState = appState
        super.init()
    }

    func show(pinnedSession: AgentSession) {
        DispatchQueue.main.async { [weak self] in
            self?.present(pinnedSession: pinnedSession)
        }
    }

    private func present(pinnedSession: AgentSession) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        let hosting = NSHostingController(
            rootView: SkillsManageView(
                pinnedSession: pinnedSession
            ) { [weak self] in self?.window?.performClose(nil) }
            .sageScaledTypography()
            .sageAccessibilityObservation()
            .environment(appState)
            .environment(AccessibilitySettings.shared)
        )

        let window = window ?? makeWindow(hosting: hosting)
        window.contentViewController = hosting
        self.window = window
        window.delegate = self
        window.level = .normal
        window.collectionBehavior = [.moveToActiveSpace]
        if !window.setFrameUsingName("SageSkillsManageWindow") {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow(hosting: NSViewController) -> NSWindow {
        let window = NSWindow(contentViewController: hosting)
        window.title = "Skills"
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isOpaque = true
        window.backgroundColor = .windowBackgroundColor
        window.hasShadow = true
        window.isMovableByWindowBackground = false
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.minSize = NSSize(width: 640, height: 440)
        window.setContentSize(NSSize(width: 720, height: 520))
        window.setFrameAutosaveName("SageSkillsManageWindow")
        return window
    }

    func windowWillClose(_ notification: Notification) {
        let otherOpen = NSApp.windows.contains {
            ($0.title == "Sage" || $0.title == "Settings" || $0.title == "Dashboard") && $0.isVisible
        }
        if !otherOpen {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
