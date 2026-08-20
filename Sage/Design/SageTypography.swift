//
//  SageTypography.swift
//  Sage
//
//  Dynamic Type–scaled metrics for agent chrome (baseline matches SageDesign.Typography).
//

import SwiftUI

struct SageTypographyMetrics: Equatable {
    var input: CGFloat
    var body: CGFloat
    var caption: CGFloat
    var title: CGFloat
    var micro: CGFloat
    var icon: CGFloat

    static let baseline = Self(
        input: SageDesign.Typography.inputSize,
        body: SageDesign.Typography.bodySize,
        caption: SageDesign.Typography.captionSize,
        title: SageDesign.Typography.titleSize,
        micro: SageDesign.Typography.microSize,
        icon: SageDesign.Typography.iconSize
    )
}

private struct SageTypographyKey: EnvironmentKey {
    static let defaultValue = SageTypographyMetrics.baseline
}

extension EnvironmentValues {
    var sageTypography: SageTypographyMetrics {
        get { self[SageTypographyKey.self] }
        set { self[SageTypographyKey.self] = newValue }
    }
}

/// Installs scaled type metrics for the subtree.
struct SageScaledTypographyModifier: ViewModifier {
    @ScaledMetric(relativeTo: .body) private var input = SageDesign.Typography.inputSize
    @ScaledMetric(relativeTo: .body) private var body = SageDesign.Typography.bodySize
    @ScaledMetric(relativeTo: .caption) private var caption = SageDesign.Typography.captionSize
    @ScaledMetric(relativeTo: .title3) private var title = SageDesign.Typography.titleSize
    @ScaledMetric(relativeTo: .caption2) private var micro = SageDesign.Typography.microSize
    @ScaledMetric(relativeTo: .caption2) private var icon = SageDesign.Typography.iconSize

    func body(content: Content) -> some View {
        content.environment(
            \.sageTypography,
            SageTypographyMetrics(
                input: input,
                body: body,
                caption: caption,
                title: title,
                micro: micro,
                icon: icon
            )
        )
    }
}

extension View {
    func sageScaledTypography() -> some View {
        modifier(SageScaledTypographyModifier())
    }

    /// Observes live accessibility settings so tokenized chrome/motion re-evaluate.
    func sageAccessibilityObservation() -> some View {
        modifier(SageAccessibilityObservationModifier())
    }
}

private struct SageAccessibilityObservationModifier: ViewModifier {
    @Environment(AccessibilitySettings.self) private var accessibility

    func body(content: Content) -> some View {
        content
            // Register dependencies so System Settings toggles refresh this subtree.
            .animation(nil, value: accessibility.revision)
    }
}
