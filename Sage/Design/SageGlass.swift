//
//  SageGlass.swift
//  Sage
//
//  Liquid Glass surfaces. Glass is for floating chrome and cards — not large
//  reading canvases. Reduce Transparency falls back to an opaque fill.
//

import AppKit
import SwiftUI

extension SageDesign {
    enum Glass {
        /// Composer and settings cards.
        static let panel: CGFloat = 12
        /// Confirmation / review cards in the transcript, dashboard tiles.
        static let card: CGFloat = 14
        /// Compact chips and code chrome.
        static let chip: CGFloat = 8
        /// Nearby glass views merge when closer than this.
        static let containerSpacing: CGFloat = 16

        /// Regular = chrome and decision cards. Clear = lighter tips and chips.
        enum Weight {
            case regular
            case clear
        }
    }
}

extension View {
    /// Rounded Liquid Glass panel used by composer, tips, settings, and dashboard.
    func sagePanelBackground(
        cornerRadius: CGFloat,
        weight: SageDesign.Glass.Weight = .regular
    ) -> some View {
        modifier(
            SageGlassSurfaceModifier(
                cornerRadius: cornerRadius,
                interactive: false,
                weight: weight
            )
        )
    }

    /// Padded glass card for confirmation and status surfaces.
    func sageGlassCard() -> some View {
        sageGlassCard(matched: nil)
    }

    /// Glass card whose material morphs between sibling cards sharing the
    /// same matched spec (e.g. plan skeleton → confirmed plan card).
    func sageGlassCard(matched: SageDesign.Glass.MatchedSpec?) -> some View {
        padding(SageDesign.Spacing.medium)
            .modifier(
                SageGlassSurfaceModifier(
                    cornerRadius: SageDesign.Glass.card,
                    interactive: false,
                    weight: .regular,
                    matched: matched
                )
            )
            .modifier(SageGlassMaterializeModifier(matched: matched))
    }

    /// Soft scroll-edge fade so content can pass under floating chrome.
    func sageScrollEdgeGlass() -> some View {
        scrollEdgeEffectStyle(.soft, for: [.top, .bottom])
    }

    /// Full-bleed titlebar / toolbar glass. Use once on the chrome stack — not
    /// on each control inside it.
    func sageGlassToolbar() -> some View {
        modifier(SageGlassToolbarModifier())
    }

    /// Materialize glass when the view is inserted, unless Reduce Motion is on.
    /// Cards with a matched spec skip materialize — the morph is their entrance.
    func sageGlassMaterialize() -> some View {
        modifier(SageGlassMaterializeModifier())
    }
}

extension SageDesign.Glass {
    @MainActor
    static var appearTransition: AnyTransition {
        if AccessibilitySettings.shared.reduceMotion {
            return .opacity
        }
        // Removal mirrors the insertion path — a card that scales up on
        // appear scales back down on exit instead of evaporating in place.
        return .opacity.combined(with: .scale(scale: 0.96))
    }

    /// Identity for a matched glass transition: two cards sharing a spec
    /// inside one `GlassEffectContainer` morph into each other instead of
    /// cross-fading, so the material reads as continuous across the swap.
    struct MatchedSpec {
        let id: String
        let namespace: Namespace.ID

        init(id: String, namespace: Namespace.ID) {
            self.id = id
            self.namespace = namespace
        }
    }

    /// Shared identity for the work-plan skeleton → confirmed plan card swap.
    static let workPlanCardMatchID = "work-plan-card"
}

extension NSWindow {
    /// Standard windows keep the system glass titlebar.
    /// Custom titlebar windows hide the separator so SwiftUI chrome owns the edge.
    func sageApplyLiquidGlass(customTitlebar: Bool) {
        titlebarSeparatorStyle = customTitlebar ? .none : .automatic
        if customTitlebar {
            titleVisibility = .hidden
            titlebarAppearsTransparent = true
        }
        sageApplyWindowMaterial()
    }

    /// Reading canvas stays opaque. Glass is only the floating chrome.
    func sageApplyWindowMaterial() {
        isOpaque = true
        backgroundColor = .windowBackgroundColor
    }

    /// Quick alpha fade for window show/hide. Animating the same property
    /// again replaces the in-flight fade, so an interrupt continues from the
    /// on-screen alpha instead of teleporting. Callers own completion safety
    /// (e.g. a generation token before `orderOut`).
    func sageFade(to alpha: CGFloat, duration: TimeInterval) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            animator().alphaValue = alpha
        }
    }

    /// Fade toward fully visible, continuing from the current on-screen alpha
    /// so a fade-out mid-flight reverses from where it is. No-op under Reduce
    /// Motion or when already fully visible.
    @MainActor
    func sageFadeIn(duration: TimeInterval) {
        guard !AccessibilitySettings.shared.reduceMotion else {
            alphaValue = 1
            return
        }
        guard alphaValue < 1 else { return }
        sageFade(to: 1, duration: duration)
    }

    /// First-presentation fade — call before `makeKeyAndOrderFront`. A window
    /// already on screen (re-focus) is never flashed through alpha 0.
    @MainActor
    func sageFadeInForPresentation() {
        guard !isVisible else { return }
        if AccessibilitySettings.shared.reduceMotion {
            alphaValue = 1
            return
        }
        alphaValue = 0
        sageFade(to: 1, duration: SageDesign.Motion.windowFadeInDuration)
    }
}

private struct SageGlassSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat
    let interactive: Bool
    var weight: SageDesign.Glass.Weight = .regular
    var matched: SageDesign.Glass.MatchedSpec? = nil
    @Environment(AccessibilitySettings.self) private var accessibility

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        Group {
            if accessibility.reduceTransparency {
                content
                    .background {
                        shape.fill(Color(nsColor: .controlBackgroundColor))
                    }
            } else {
                content
                    .glassEffect(resolvedGlass, in: shape)
                    .sageMatchedGlassID(
                        accessibility.reduceMotion ? nil : matched
                    )
            }
        }
        .overlay {
            if accessibility.increaseContrast || accessibility.reduceTransparency {
                shape.strokeBorder(
                    Color.primary.opacity(accessibility.strokeOpacity),
                    lineWidth: 1
                )
            }
        }
    }

    private var resolvedGlass: Glass {
        let base: Glass = weight == .clear ? .clear : .regular
        return interactive ? base.interactive() : base
    }
}

private extension View {
    @ViewBuilder
    func sageMatchedGlassID(_ matched: SageDesign.Glass.MatchedSpec?) -> some View {
        if let matched {
            glassEffectID(matched.id, in: matched.namespace)
        } else {
            self
        }
    }
}

private struct SageGlassToolbarModifier: ViewModifier {
    @Environment(AccessibilitySettings.self) private var accessibility

    func body(content: Content) -> some View {
        Group {
            if accessibility.reduceTransparency {
                content
                    .background(Color(nsColor: .windowBackgroundColor))
            } else {
                content
                    .glassEffect(.regular, in: Rectangle())
            }
        }
        .overlay(alignment: .bottom) {
            if accessibility.increaseContrast {
                Rectangle()
                    .fill(Color.primary.opacity(accessibility.strokeOpacity))
                    .frame(height: 1)
            }
        }
    }
}

private struct SageGlassMaterializeModifier: ViewModifier {
    var matched: SageDesign.Glass.MatchedSpec? = nil
    @Environment(AccessibilitySettings.self) private var accessibility

    func body(content: Content) -> some View {
        if accessibility.reduceMotion || matched != nil {
            // Deliberate hard skip under Reduce Motion, not an oversight:
            // transcript content appends are instant under RM (streaming
            // animations are nil), so a solo fade here would make this the
            // only moving element in a still feed. Paired `.transition`
            // fallbacks at the call sites handle the inserted-chrome cases.
            content
        } else {
            content.glassEffectTransition(.materialize)
        }
    }
}
