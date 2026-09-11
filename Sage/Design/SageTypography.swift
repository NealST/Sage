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
    var reading: CGFloat
    var caption: CGFloat
    var title: CGFloat
    var micro: CGFloat
    var icon: CGFloat

    static let baseline = Self(
        input: SageDesign.Typography.inputSize,
        body: SageDesign.Typography.bodySize,
        reading: SageDesign.Typography.readingSize,
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
    @ScaledMetric(relativeTo: .body) private var reading = SageDesign.Typography.readingSize
    @ScaledMetric(relativeTo: .caption) private var caption = SageDesign.Typography.captionSize
    @ScaledMetric(relativeTo: .title3) private var title = SageDesign.Typography.titleSize
    @ScaledMetric(relativeTo: .caption) private var micro = SageDesign.Typography.microSize
    @ScaledMetric(relativeTo: .caption) private var icon = SageDesign.Typography.iconSize

    func body(content: Content) -> some View {
        content.environment(
            \.sageTypography,
            SageTypographyMetrics(
                input: input,
                body: body,
                reading: reading,
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

    /// The single constructor for chrome fonts — the audit point for the
    /// weight vocabulary: hierarchy is regular / medium / semibold (bold only
    /// for icon glyphs). Sizes come from `sageTypography` metrics; hardcoded
    /// sizes here are reviewable in one place.
    func sageFont(
        _ size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default
    ) -> some View {
        font(.system(size: size, weight: weight, design: design))
    }

    /// Observes live accessibility settings so tokenized chrome/motion re-evaluate.
    func sageAccessibilityObservation() -> some View {
        modifier(SageAccessibilityObservationModifier())
    }

    /// 11pt chrome text carries a slight positive tracking bump — dense
    /// captions read looser and legible at that size, mirroring how SF's
    /// tracking tables tighten large text and relax small text.
    func sageMicro(
        _ size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default
    ) -> some View {
        font(.system(size: size, weight: weight, design: design))
            .tracking(0.2)
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
