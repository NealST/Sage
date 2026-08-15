import AppKit
import SwiftUI

/// One macOS agent window bound to a single `AgentSession` (General or a Project).
@MainActor
final class AgentWindowController: NSObject, NSWindowDelegate {
    private let appState: AppState
    private let session: AgentSession
    private var window: NSWindow?

    var isVisible: Bool { window?.isVisible == true }

    init(appState: AppState, session: AgentSession) {
        self.appState = appState
        self.session = session
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
        appState.noteSessionBecameKey(session)

        DispatchQueue.main.async { [session] in
            NotificationCenter.default.post(
                name: .sageFocusAgentInput,
                object: session.id
            )
        }
    }

    /// Hiding never cancels a pending plan — only explicit Cancel does.
    /// General window hides; project windows stay available until destroyed.
    func hide() {
        window?.orderOut(nil)
        appState.noteSessionHidden(session)
        let anyVisible = NSApp.windows.contains {
            $0.isVisible && $0.identifier?.rawValue.hasPrefix("SageAgentWindow") == true
        }
        let settingsOpen = NSApp.windows.contains { $0.title == "Settings" && $0.isVisible }
        if !anyVisible && !settingsOpen {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    /// Tear down the NSWindow (project window close).
    func destroy() {
        window?.delegate = nil
        window?.orderOut(nil)
        window?.contentView = nil
        window = nil
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
        window.title = session.isGeneral
            ? "Sage"
            : (session.agent.state.focusedProject?.name ?? "Opening…")
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

        let autosave = session.windowAutosaveName
        window.identifier = NSUserInterfaceItemIdentifier(autosave)
        window.setFrameAutosaveName(autosave)

        let root = AgentPanelView()
            .environment(appState)
            .environment(session)
            .environment(AccessibilitySettings.shared)
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.autoresizingMask = [.width, .height]
        window.contentView = hosting

        return window
    }

    private func position(_ window: NSWindow) {
        if window.setFrameUsingName(window.frameAutosaveName) {
            return
        }
        let screen = screenForWindow()
        let visible = screen.visibleFrame
        let size = window.frame.size
        // Cascade project windows slightly so they don't fully overlap General.
        let offset: CGFloat
        switch session.kind {
        case .general:
            offset = 0
        case .project:
            offset = CGFloat(appState.projectSessions.count) * 22
        }
        let x = visible.midX - size.width / 2 + offset
        let y = visible.midY - size.height / 2 - offset
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
        switch session.kind {
        case .general:
            hide()
            return false
        case .project(let id):
            Task { @MainActor in
                await appState.closeProjectWindow(projectID: id)
            }
            return false
        }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        appState.noteSessionBecameKey(session)
        NSApp.setActivationPolicy(.regular)
        NotificationCenter.default.post(
            name: .sageFocusAgentInput,
            object: session.id
        )
    }
}

extension Notification.Name {
    static let sageFocusAgentInput = Notification.Name("sage.focusAgentInput")
}
