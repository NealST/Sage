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
    /// Shared with the SwiftUI editor — carries dirty state so close can be vetoed.
    private let editSession = SkillsEditSession()
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
        editSession.reset()

        let hosting = NSHostingController(
            rootView: SkillsManageView(
                pinnedSession: pinnedSession,
                onDone: { [weak self] in self?.window?.performClose(nil) },
                editSession: editSession
            )
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
            window.setFrame(AppState.cascadeCenteredFrame(for: window), display: false)
        }
        window.sageFadeInForPresentation()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow(hosting: NSViewController) -> NSWindow {
        let window = NSWindow(contentViewController: hosting)
        window.title = "Skills"
        window.identifier = NSUserInterfaceItemIdentifier(AppState.WindowIdentifier.skillsManage)
        window.titleVisibility = .visible
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.sageApplyLiquidGlass(customTitlebar: false)
        window.hasShadow = true
        window.isMovableByWindowBackground = false
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.minSize = NSSize(width: 640, height: 440)
        window.setContentSize(NSSize(width: 720, height: 520))
        window.setFrameAutosaveName("SageSkillsManageWindow")
        return window
    }

    /// Red traffic light / Cmd-W while edits are unsaved: veto and let the
    /// view present its save/discard alert. `onDone` re-triggers
    /// `performClose` once the alert resolves.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if editSession.isDirty {
            editSession.closeRequestID = UUID()
            return false
        }
        return true
    }

    func windowWillClose(_ notification: Notification) {
        AppState.demoteToAccessoryIfNeeded(
            excluding: notification.object as? NSWindow
        )
    }
}
