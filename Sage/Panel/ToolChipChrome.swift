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

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: SageDesign.Glass.card, style: .continuous)
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
    func sageToolChipSurface(warning: Bool = false) -> some View {
        modifier(ToolChipSurfaceModifier(warning: warning))
    }
}

/// Header press feedback for disclosure chips — dim + micro-scale on press.
struct ToolChipHeaderButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(SageDesign.Motion.pressFeedback, value: configuration.isPressed)
    }
}
