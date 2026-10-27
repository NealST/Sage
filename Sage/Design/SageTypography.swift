//
//  SageTypography.swift
//  Sage
//
//  App text-size–scaled metrics for agent chrome (baseline matches SageDesign.Typography).
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

    /// App text-size scaling (macOS has no Dynamic Type channel). Fractional
    /// results round to the half point so rasterized text stays crisp.
    func scaled(by factor: CGFloat) -> Self {
        func size(_ value: CGFloat) -> CGFloat {
            (value * factor * 2).rounded() / 2
        }
        return Self(
            input: size(input),
            body: size(body),
            reading: size(reading),
            caption: size(caption),
            title: size(title),
            micro: size(micro),
            icon: size(icon)
        )
    }
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

/// Installs app text-size–scaled metrics for the subtree. Reading
/// `SageTextSizeSettings.shared` during body evaluation registers the
/// Observation dependency, so Settings changes propagate live.
struct SageScaledTypographyModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.environment(
            \.sageTypography,
            SageTypographyMetrics.baseline.scaled(by: SageTextSizeSettings.shared.scale)
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

    /// 11pt chrome text. SF's own tracking tables already relax small sizes,
    /// so no manual adjustment is layered on top (HIG: only mockups hand-tune
    /// tracking — the running system font adjusts it dynamically).
    func sageMicro(
        _ size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default
    ) -> some View {
        font(.system(size: size, weight: weight, design: design))
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
