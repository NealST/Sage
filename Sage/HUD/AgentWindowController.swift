import AppKit
import SwiftUI

/// One macOS agent window bound to a single `AgentSession` (General or a Project).
@MainActor
final class AgentWindowController: NSObject, NSWindowDelegate {
    private let appState: AppState
    private let session: AgentSession
    private var window: NSWindow?
    /// Increments on every show/hide/destroy — a stale fade-out completion
    /// must not order the window out after a later show revived it.
    private var fadeGeneration: UInt = 0

    var isVisible: Bool { window?.isVisible == true }

    /// The user's attention is on this window right now. App activation alone
    /// is the wrong signal — being in Settings or another project's window
    /// keeps the app active while this transcript goes unwatched.
    var isKey: Bool { window?.isKeyWindow == true }

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
                requestComposerFocus()
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
        // A pending fade-out's orderOut is voided by bumping the generation;
        // if the fade was mid-flight the window continues back up from its
        // current on-screen alpha instead of teleporting to fully visible.
        fadeGeneration &+= 1
        window.sageFadeIn(duration: SageDesign.Motion.windowFadeInDuration)
        focus(window)
        appState.noteSessionBecameKey(session)
        requestComposerFocus()
    }

    /// Hiding never cancels a pending plan — only explicit Cancel does.
    /// General window hides; project windows stay available until destroyed.
    func hide() {
        guard let window else { return }
        appState.noteSessionHidden(session)
        fadeGeneration &+= 1
        let generation = fadeGeneration
        if AccessibilitySettings.shared.reduceMotion {
            window.alphaValue = 1
            window.orderOut(nil)
            AppState.demoteToAccessoryIfNeeded()
            return
        }
        window.sageFade(to: 0, duration: SageDesign.Motion.windowFadeOutDuration)
        // NSAnimationContext completions can fire early when the animation is
        // replaced (fast toggle), so the generation token is the source of
        // truth — orderOut only happens if no show/hide happened since.
        DispatchQueue.main.asyncAfter(
            deadline: .now() + SageDesign.Motion.windowFadeOutDuration + 0.01
        ) { [weak self] in
            guard let self, fadeGeneration == generation else { return }
            window.orderOut(nil)
            appState.noteSessionHidden(session)
            AppState.demoteToAccessoryIfNeeded()
        }
    }

    /// Tear down the NSWindow (project window close).
    func destroy() {
        fadeGeneration &+= 1
        window?.alphaValue = 1
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
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenPrimary]
        window.minSize = NSSize(width: 560, height: 440)
        window.sageApplyLiquidGlass(customTitlebar: true)
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
            // Keep cascaded windows fully on-screen, even with many projects
            // or a small display.
            let maxOffset = max(
                0,
                min(visible.width - size.width, visible.height - size.height) / 2
            )
            offset = min(CGFloat(appState.projectSessions.count) * 22, maxOffset)
        }
        let originX = visible.midX - size.width / 2 + offset
        let originY = visible.midY - size.height / 2 - offset
        window.setFrame(NSRect(origin: NSPoint(x: originX, y: originY), size: size), display: true)
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
        // Clicking the transcript to select text also makes the window key.
        // Only the hotkey / show path requests composer focus.
    }

    /// Hotkey and first show — not every time the window becomes key.
    private func requestComposerFocus() {
        DispatchQueue.main.async { [session] in
            NotificationCenter.default.post(
                name: .sageFocusAgentInput,
                object: session.id
            )
        }
    }
}

extension Notification.Name {
    static let sageFocusAgentInput = Notification.Name("sage.focusAgentInput")
    /// Menu command → workspace tab switch. Object: `AgentSession.Kind`.
    static let sageSelectWorkspaceTab = Notification.Name("sage.selectWorkspaceTab")
    /// Menu command → open the task-history browser. Object: `AgentSession.Kind`.
    static let sageBrowseTaskHistory = Notification.Name("sage.browseTaskHistory")
    /// Menu command → open the transcript find bar. Object: `AgentSession.Kind`.
    static let sageFindInTranscript = Notification.Name("sage.findInTranscript")
}
