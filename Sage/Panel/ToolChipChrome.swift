//
//  ToolChipChrome.swift
//  Sage
//
//  Shared chrome for tool-call / tool-result chips so the two views can't drift.
//

import SwiftUI

enum ToolChipChrome {
    /// Disclosure expand/collapse — content slides down from the header on
    /// expand and retraces back up into it on collapse. Reduce Motion
    /// collapses it to an opacity swap.
    static var expandTransition: AnyTransition {
        if AccessibilityPreferences.reduceMotion {
            return .opacity
        }
        return .opacity.combined(with: .move(edge: .top))
    }
}

/// Passive chip surface over the reading canvas — translucent tint, never
/// glass; contrast stroke only when Increase Contrast asks for it.
struct ToolChipSurfaceModifier: ViewModifier {
    /// Mutating steps read warmer (warning tint) so their weight is scannable.
    var warning: Bool = false
    var cornerRadius: CGFloat = SageDesign.Glass.chip

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(
                shape.fill(
                    warning
                        ? SageDesign.Palette.warning.opacity(SageDesign.Chrome.diffFillOpacity)
                        : Color.primary.opacity(SageDesign.Chrome.pillFillOpacity)
                )
            )
            .overlay {
                if AccessibilityPreferences.increaseContrast {
                    shape.strokeBorder(
                        Color.primary.opacity(SageDesign.Chrome.strokeOpacity),
                        lineWidth: 1
                    )
                }
            }
            .clipShape(shape)
    }
}

extension View {
    func sageToolChipSurface(
        warning: Bool = false,
        cornerRadius: CGFloat = SageDesign.Glass.chip
    ) -> some View {
        modifier(ToolChipSurfaceModifier(warning: warning, cornerRadius: cornerRadius))
    }
}

/// Header press feedback for disclosure chips — dim + micro-scale on press,
/// plus a light hover fill so the transcript's most-tappable element
/// announces itself before the click (only when enabled: a non-expandable
/// chip must not read as interactive).
struct ToolChipHeaderButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ToolChipHeader(configuration: configuration)
    }
}

private struct ToolChipHeader: View {
    let configuration: ButtonStyle.Configuration
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        // Top corners match the chip radius; the square bottom edge is
        // clipped by the chip's own rounded shape when collapsed.
        let hoverShape = UnevenRoundedRectangle(
            topLeadingRadius: SageDesign.Glass.chip,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: SageDesign.Glass.chip,
            style: .continuous
        )
        configuration.label
            .background(
                hoverShape.fill(
                    Color.primary.opacity(
                        isHovered && isEnabled
                            ? SageDesign.Chrome.pillFillOpacity
                            : 0
                    )
                )
            )
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .onHover { hovered in
                isHovered = hovered && isEnabled
            }
            .animation(hoverAnimation, value: isHovered)
            .animation(SageDesign.Motion.pressFeedback, value: configuration.isPressed)
    }

    private var hoverAnimation: Animation? {
        reduceMotion ? nil : SageDesign.Motion.reducedCrossFade
    }
}
