//
//  SkillTipChrome.swift
//  Sage
//
//  Shared visual chrome for skill tips and panel surfaces.
//

import SwiftUI

enum SkillTipChrome {
    @MainActor
    static var bannerTransition: AnyTransition {
        if AccessibilitySettings.shared.reduceMotion {
            return .opacity
        }
        return .asymmetric(
            insertion: .opacity.combined(with: .move(edge: .bottom)),
            removal: .opacity.combined(with: .move(edge: .bottom))
        )
    }

    @ViewBuilder
    static func icon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: SageDesign.Typography.captionSize, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 16, height: 16)
            .padding(.top, 2)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    static func dismissButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.tertiary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Dismiss")
        .accessibilityLabel("Dismiss")
    }

    @ViewBuilder
    static func bannerStack<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: SageDesign.Spacing.xs) {
            content()
        }
        .padding(.horizontal, SageDesign.Spacing.lg)
        .padding(.vertical, SageDesign.Spacing.sm)
        .transition(bannerTransition)
    }

    @ViewBuilder
    static func row<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .sagePanelBackground(cornerRadius: 10)
    }
}

extension View {
    /// Shared fill + optional contrast stroke used by tips, settings cards, dashboard, composer.
    func sagePanelBackground(cornerRadius: CGFloat) -> some View {
        modifier(SagePanelBackgroundModifier(cornerRadius: cornerRadius))
    }
}

private struct SagePanelBackgroundModifier: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(AccessibilitySettings.self) private var accessibility

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.primary.opacity(accessibility.fillOpacity))
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        Color.primary.opacity(
                            accessibility.increaseContrast ? accessibility.strokeOpacity : 0
                        ),
                        lineWidth: accessibility.increaseContrast ? 1 : 0
                    )
            }
    }
}
