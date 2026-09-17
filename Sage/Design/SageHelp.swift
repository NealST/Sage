//
//  SageHelp.swift
//  Sage
//
//  Fast rounded hover labels for chrome icons. Replaces `.help()`, whose
//  system tooltip is delayed (~1s) and drawn as a square window.
//

import AppKit
import SwiftUI

extension View {
    /// Hover label under a chrome control. Replaces `.help` so the label
    /// appears quickly and with rounded corners.
    func sageHelp(_ text: String) -> some View {
        modifier(SageHelpModifier(text: text))
    }
}

private struct SageHelpModifier: ViewModifier {
    let text: String
    @State private var anchor = HelpAnchor()

    func body(content: Content) -> some View {
        content
            .background {
                HelpAnchorView(anchor: anchor)
            }
            .onHover { hovering in
                anchor.text = text
                anchor.isHovering = hovering
                if hovering, let view = anchor.view {
                    SageHelpOverlay.shared.scheduleShow(text: text, from: view)
                } else if !hovering {
                    SageHelpOverlay.shared.scheduleHide(for: text)
                }
            }
    }
}

private final class HelpAnchor {
    weak var view: NSView?
    var text = ""
    var isHovering = false
}

private struct HelpAnchorView: NSViewRepresentable {
    let anchor: HelpAnchor

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.setAccessibilityElement(false)
        attach(view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        attach(nsView)
    }

    private func attach(_ view: NSView) {
        let wasUnattached = anchor.view == nil
        anchor.view = view
        if wasUnattached, anchor.isHovering, !anchor.text.isEmpty {
            SageHelpOverlay.shared.scheduleShow(text: anchor.text, from: view)
        }
    }
}

@MainActor
final class SageHelpOverlay {
    static let shared = SageHelpOverlay()

    private var panel: NSPanel?
    private var hosting: NSHostingView<SageHelpLabel>?
    private var showTask: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?
    private var currentText: String?
    private var mouseDownMonitor: Any?
    private var observers: [NSObjectProtocol] = []

    private init() {
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: NSWindow.didResignKeyNotification, object: nil, queue: .main) { [weak self] note in
                Task { @MainActor in
                    guard let self else { return }
                    guard let window = note.object as? NSWindow, window === self.panel?.parent else { return }
                    self.hide()
                }
            },
            center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.hide() }
            },
            center.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { [weak self] note in
                Task { @MainActor in
                    guard let self else { return }
                    guard let window = note.object as? NSWindow, window === self.panel?.parent else { return }
                    self.hide()
                }
            }
        ]
    }

    func scheduleShow(text: String, from view: NSView) {
        guard !text.isEmpty else { return }
        hideTask?.cancel()
        hideTask = nil

        if currentText == text, panel?.isVisible == true {
            reposition(from: view)
            return
        }

        let immediate = panel?.isVisible == true
        showTask?.cancel()
        showTask = Task { [weak self] in
            if !immediate {
                try? await Task.sleep(for: .seconds(SageDesign.Motion.helpShowDelay))
            }
            guard !Task.isCancelled else { return }
            self?.show(text: text, from: view)
        }
    }

    func scheduleHide(for text: String) {
        showTask?.cancel()
        showTask = nil
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(SageDesign.Motion.helpHideGrace))
            guard !Task.isCancelled else { return }
            guard self?.currentText == text else { return }
            self?.hide()
        }
    }

    private func show(text: String, from view: NSView) {
        guard view.window != nil, !view.isHiddenOrHasHiddenAncestor else { return }
        currentText = text

        let label = SageHelpLabel(
            text: text,
            increaseContrast: AccessibilitySettings.shared.increaseContrast
        )
        let hosting = self.hosting ?? NSHostingView(rootView: label)
        hosting.rootView = label
        hosting.appearance = view.effectiveAppearance
        hosting.sizingOptions = [.intrinsicContentSize]
        hosting.layoutSubtreeIfNeeded()
        var size = hosting.fittingSize
        if size.width < 1 || size.height < 1 {
            size = hosting.intrinsicContentSize
        }

        let panel = self.panel ?? makePanel()
        if hosting.superview !== panel.contentView {
            panel.contentView = hosting
        }
        panel.setContentSize(size)
        self.hosting = hosting
        self.panel = panel

        attach(panel, to: view.window)
        reposition(from: view, size: size)
        installMouseDownMonitor()
        if !panel.isVisible {
            panel.orderFront(nil)
        }
    }

    private func hide() {
        showTask?.cancel()
        showTask = nil
        hideTask?.cancel()
        hideTask = nil
        currentText = nil
        removeMouseDownMonitor()
        panel?.orderOut(nil)
    }

    private func installMouseDownMonitor() {
        guard mouseDownMonitor == nil else { return }
        mouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            Task { @MainActor in self?.hide() }
            return event
        }
    }

    private func removeMouseDownMonitor() {
        if let mouseDownMonitor {
            NSEvent.removeMonitor(mouseDownMonitor)
            self.mouseDownMonitor = nil
        }
    }

    private func reposition(from view: NSView, size: CGSize? = nil) {
        guard let panel, let window = view.window else { return }
        let size = size ?? panel.frame.size
        let local = view.convert(view.bounds, to: nil)
        let anchor = window.convertToScreen(local)
        let visible = window.screen?.visibleFrame ?? anchor
        panel.setFrameOrigin(
            Self.origin(anchor: anchor, size: size, visible: visible)
        )
    }

    private func attach(_ panel: NSPanel, to window: NSWindow?) {
        guard let window else { return }
        if panel.parent !== window {
            panel.parent?.removeChildWindow(panel)
            window.addChildWindow(panel, ordered: .above)
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = true
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
        panel.animationBehavior = .none
        return panel
    }

    /// Screen-space origin: centered under the control, flipped above if the
    /// label would leave the visible frame. `size` includes the shadow inset
    /// around the rounded label, which is subtracted so the visible card
    /// sits `helpGap` below the control.
    static func origin(
        anchor: CGRect,
        size: CGSize,
        visible: CGRect
    ) -> CGPoint {
        let gap = SageDesign.Motion.helpGap
        let inset = SageHelpLabel.shadowInset
        let margin: CGFloat = 6
        var x = anchor.midX - size.width / 2
        var y = anchor.minY - gap - size.height + inset
        let minX = visible.minX + margin
        let maxX = visible.maxX - size.width - margin
        if maxX >= minX {
            x = min(max(x, minX), maxX)
        }
        if y < visible.minY - inset {
            y = anchor.maxY + gap - inset
        }
        return CGPoint(x: x, y: y)
    }
}

private struct SageHelpLabel: View {
    static let shadowInset: CGFloat = 12

    let text: String
    var increaseContrast: Bool

    var body: some View {
        Text(text)
            .font(.system(size: SageDesign.Typography.microSize))
            .foregroundStyle(.primary)
            .padding(.horizontal, SageDesign.Spacing.small)
            .padding(.vertical, SageDesign.Spacing.extraSmall)
            .background {
                let shape = RoundedRectangle(
                    cornerRadius: SageDesign.Glass.tooltip,
                    style: .continuous
                )
                shape.fill(Color(nsColor: .controlBackgroundColor))
                    .overlay {
                        if increaseContrast {
                            shape.strokeBorder(
                                Color.primary.opacity(SageDesign.Chrome.strokeOpacity),
                                lineWidth: 1
                            )
                        }
                    }
                    .shadow(color: .black.opacity(0.16), radius: 8, y: 2)
            }
            .padding(Self.shadowInset)
            .fixedSize()
    }
}
