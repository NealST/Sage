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
        /// System glass buttons that stay a rounded rect, not a capsule.
        static let button: CGFloat = 10
        /// Sub-chip clips (attachment thumbnails).
        static let mini: CGFloat = 4
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
    func sageScrollEdgeGlass(edges: Edge.Set = [.top, .bottom]) -> some View {
        scrollEdgeEffectStyle(.soft, for: edges)
            .scrollIndicators(.never)
    }

    /// Small interactive glass capsule for toolbar controls — the floating-chip
    /// idiom Liquid Glass windows are built for. Hover and press show in the
    /// material itself. Reduce Transparency falls back to the quiet pill fill;
    /// Increase Contrast adds a hairline stroke.
    func sageGlassChip() -> some View {
        modifier(SageGlassChipModifier())
    }

    /// System Liquid Glass button — rounded rect, not a capsule.
    func sageGlassButton(_ size: ControlSize = .small) -> some View {
        buttonStyle(.glass)
            .buttonBorderShape(.roundedRectangle(radius: SageDesign.Glass.button))
            .controlSize(size)
    }

    /// Prominent sibling of `sageGlassButton` (Send / Run / Allow).
    func sageGlassProminentButton(_ size: ControlSize = .regular) -> some View {
        buttonStyle(.glassProminent)
            .buttonBorderShape(.roundedRectangle(radius: SageDesign.Glass.button))
            .controlSize(size)
    }

    /// Tinted glass capsule for attention states — the material itself
    /// carries the color (the one Liquid Glass capability the semantic
    /// fills can't express). Reduce Transparency falls back to the tinted
    /// fill; callers pick a foreground color that stays legible in both.
    func sageTintedGlassCapsule(_ tint: Color) -> some View {
        modifier(SageGlassTintedCapsuleModifier(tint: tint))
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
            // An empty system toolbar reserves the standard unified-toolbar
            // band and drops the traffic lights to their native position
            // (x 18, centerline y 26 — matching Finder). Without it the lights
            // sit high in a short band while SwiftUI chrome, pushed down by
            // the hosting view's safe area, renders as a second stacked
            // toolbar instead of one row with the lights.
            toolbar = NSToolbar(identifier: "SageChrome")
        }
        sageApplyWindowMaterial()
    }

    /// On macOS 26 the system renders this as the Liquid Glass window body —
    /// the same material Calculator and System Settings use — which is why the
    /// reading canvas must stay unpainted in SwiftUI: a `Color(.windowBackgroundColor)`
    /// fill resolves to flat graphite (rgb 30,30,30) and covers the material,
    /// clashing with the glass frame and chrome. App-drawn glass stays reserved
    /// for floating chrome and cards; the body material belongs to the system.
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

private struct SageGlassChipModifier: ViewModifier {
    @Environment(AccessibilitySettings.self) private var accessibility

    func body(content: Content) -> some View {
        let shape = Capsule(style: .continuous)
        Group {
            if accessibility.reduceTransparency {
                content
                    .background {
                        shape.fill(Color.primary.opacity(SageDesign.Chrome.pillFillOpacity))
                    }
            } else {
                content
                    .glassEffect(.regular.interactive(), in: shape)
            }
        }
        .overlay {
            if accessibility.increaseContrast {
                shape.strokeBorder(
                    Color.primary.opacity(accessibility.strokeOpacity),
                    lineWidth: 1
                )
            }
        }
    }
}

private struct SageGlassTintedCapsuleModifier: ViewModifier {
    let tint: Color
    @Environment(AccessibilitySettings.self) private var accessibility

    func body(content: Content) -> some View {
        let shape = Capsule(style: .continuous)
        Group {
            if accessibility.reduceTransparency {
                content
                    .background {
                        shape.fill(tint.opacity(0.14))
                    }
            } else {
                content
                    .glassEffect(.regular.tint(tint), in: shape)
            }
        }
        .overlay {
            if accessibility.increaseContrast {
                shape.strokeBorder(
                    Color.primary.opacity(accessibility.strokeOpacity),
                    lineWidth: 1
                )
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
