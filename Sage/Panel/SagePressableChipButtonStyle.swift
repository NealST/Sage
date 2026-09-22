//
//  SagePressableChipButtonStyle.swift
//  Sage
//

import SwiftUI

/// Instant press feedback — glass capsule; scale only when Reduce Motion is off.
struct SagePressableChipButtonStyle: ButtonStyle {
    var emphasized: Bool = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AccessibilitySettings.self) private var accessibility

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return Group {
            if accessibility.reduceTransparency {
                configuration.label
                    .frame(minHeight: SageDesign.Control.minimumHitTarget)
                    .background {
                        RoundedRectangle(cornerRadius: SageDesign.Glass.button, style: .continuous)
                            .fill(
                                Color.primary.opacity(
                                    pressed
                                        ? SageDesign.Chrome.selectionFillOpacity
                                        : (emphasized
                                            ? SageDesign.Chrome.strongFillOpacity
                                            : SageDesign.Chrome.fillOpacity)
                                )
                            )
                    }
            } else {
                configuration.label
                    .frame(minHeight: SageDesign.Control.minimumHitTarget)
                    .glassEffect(
                        .clear.interactive(),
                        in: RoundedRectangle(cornerRadius: SageDesign.Glass.button, style: .continuous)
                    )
            }
        }
        .contentShape(Rectangle())
        .opacity(isEnabled ? 1 : SageDesign.Chrome.disabledControlOpacity)
        .scaleEffect(pressed && !reduceMotion ? 0.97 : 1)
        .animation(SageDesign.Motion.pressFeedback, value: pressed)
    }
}

/// Quiet text actions on content surfaces ("Show more", "Merge") — a soft
/// hover fill plus press micro-scale so affordance exists before the click.
/// The flat sibling of `SagePressableChipButtonStyle`, which is a glass
/// capsule for floating chrome; this one stays flat over cards and diffs.
/// Labels are grown to the 28pt hit floor so quiet text stays comfortably
/// tappable even when the caller draws it bare.
struct SagePlainActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SagePlainActionLabel(configuration: configuration)
    }
}

private struct SagePlainActionLabel: View {
    let configuration: ButtonStyle.Configuration
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .frame(minHeight: SageDesign.Control.minimumHitTarget)
            .background(
                RoundedRectangle(cornerRadius: SageDesign.Glass.chip, style: .continuous)
                    .fill(Color.primary.opacity(fillOpacity))
            )
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : SageDesign.Chrome.disabledControlOpacity)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .onHover { hovered in isHovered = hovered && isEnabled }
            .animation(hoverAnimation, value: isHovered)
            .animation(SageDesign.Motion.pressFeedback, value: configuration.isPressed)
    }

    private var fillOpacity: Double {
        if configuration.isPressed { return SageDesign.Chrome.selectionFillOpacity }
        return isHovered && isEnabled ? SageDesign.Chrome.pillFillOpacity : 0
    }

    private var hoverAnimation: Animation? {
        reduceMotion ? nil : SageDesign.Motion.reducedCrossFade
    }
}

/// One dismiss control app-wide — the same xmark, size, hover treatment,
/// and hit target wherever something can be closed.
struct SageDismissButton: View {
    let action: () -> Void
    /// Spoken label (and default tooltip) — says what dismissing keeps or
    /// hides, not just "Dismiss".
    var label: String = "Dismiss"
    var help: String?

    @Environment(\.sageTypography) private var type

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .sageFont(type.caption, weight: .semibold)
                .foregroundStyle(.secondary)
                .frame(
                    width: SageDesign.Control.minimumHitTarget,
                    height: SageDesign.Control.minimumHitTarget
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(SagePlainActionButtonStyle())
        .help(help ?? label)
        .accessibilityLabel(label)
    }
}
