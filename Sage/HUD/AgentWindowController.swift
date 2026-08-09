//
//  AgentWindowController.swift
//  Sage
//

import AppKit
import SwiftUI

/// Persistent macOS agent workspace window (close / minimize / zoom).
@MainActor
final class AgentWindowController: NSObject, NSWindowDelegate {
    private let appState: AppState
    private var window: NSWindow?

    init(appState: AppState) {
        self.appState = appState
        super.init()
    }

    func toggle() {
        if let window, window.isVisible {
            if window.isKeyWindow {
                hide()
            } else {
                focus(window)
            }
        } else {
            show()
        }
    }

    func show() {
        let window = window ?? makeWindow()
        self.window = window

        if window.frame.origin == .zero || !window.isVisible {
            position(window)
        }

        NSApp.setActivationPolicy(.regular)
        focus(window)
        appState.isAgentWindowVisible = true

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .sageFocusAgentInput, object: nil)
        }
    }

    /// Hiding never cancels a pending plan — only explicit Cancel does.
    func hide() {
        window?.orderOut(nil)
        appState.isAgentWindowVisible = false
        // Stay regular if Settings is still open; otherwise return to menu-bar agent.
        let settingsOpen = NSApp.windows.contains { $0.title == "Settings" && $0.isVisible }
        if !settingsOpen {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    private func focus(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let size = NSSize(width: SageDesign.Panel.width, height: SageDesign.Panel.height)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.delegate = self
        window.title = "Sage"
        // General chrome owns the titlebar row — hide the stacked system title.
        // Project mode re-enables title + representedURL from AgentWorkspaceView.
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenPrimary]
        window.minSize = NSSize(width: 560, height: 440)
        window.isOpaque = true
        window.backgroundColor = NSColor.windowBackgroundColor
        window.hasShadow = true
        window.hidesOnDeactivate = false
        window.animationBehavior = .documentWindow
        window.identifier = NSUserInterfaceItemIdentifier("SageAgentWindow")
        window.setFrameAutosaveName("SageAgentWindow")

        let root = AgentPanelView()
            .environment(appState)
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.autoresizingMask = [.width, .height]
        window.contentView = hosting

        return window
    }

    private func position(_ window: NSWindow) {
        // Honor autosaved frame when available.
        if window.setFrameUsingName("SageAgentWindow") {
            return
        }
        let screen = screenForWindow()
        let visible = screen.visibleFrame
        let size = window.frame.size
        let x = visible.midX - size.width / 2
        let y = visible.midY - size.height / 2
        window.setFrame(NSRect(origin: NSPoint(x: x, y: y), size: size), display: true)
    }

    private func screenForWindow() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) {
            return screen
        }
        return NSScreen.main ?? NSScreen.screens[0]
    }

    // MARK: - NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hide()
        return false
    }

    func windowDidBecomeKey(_ notification: Notification) {
        appState.isAgentWindowVisible = true
        NSApp.setActivationPolicy(.regular)
        NotificationCenter.default.post(name: .sageFocusAgentInput, object: nil)
    }
}

extension Notification.Name {
    static let sageFocusAgentInput = Notification.Name("sage.focusAgentInput")
}
