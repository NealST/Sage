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
        /// Composer, settings cards, dashboard tiles.
        static let panel: CGFloat = 12
        /// Confirmation / review cards in the transcript.
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
        padding(SageDesign.Spacing.medium)
            .sagePanelBackground(cornerRadius: SageDesign.Glass.card)
            .sageGlassMaterialize()
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
        return .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.96)),
            removal: .opacity
        )
    }
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
    }
}

private struct SageGlassSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat
    let interactive: Bool
    var weight: SageDesign.Glass.Weight = .regular
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
    @Environment(AccessibilitySettings.self) private var accessibility

    func body(content: Content) -> some View {
        if accessibility.reduceMotion {
            content
        } else {
            content.glassEffectTransition(.materialize)
        }
    }
}
