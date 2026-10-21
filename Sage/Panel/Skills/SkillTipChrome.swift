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
        SageDesign.Glass.appearTransition
    }

    @ViewBuilder
    static func icon(_ systemName: String) -> some View {
        SkillTipChromeIcon(systemName: systemName)
    }

    @ViewBuilder
    static func dismissButton(action: @escaping () -> Void) -> some View {
        SageDismissButton(action: action)
    }

    @ViewBuilder
    static func bannerStack<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: SageDesign.Spacing.extraSmall) {
            content()
        }
        .padding(.horizontal, SageDesign.Spacing.large)
        .padding(.vertical, SageDesign.Spacing.small)
        .transition(bannerTransition)
    }

    @ViewBuilder
    static func row<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, SageDesign.Spacing.chipHorizontal)
            .padding(.vertical, SageDesign.Spacing.chipVertical)
            .sagePanelBackground(cornerRadius: SageDesign.Glass.card, weight: .clear)
            .sageGlassMaterialize()
    }
}

private struct SkillTipChromeIcon: View {
    let systemName: String
    @Environment(\.sageTypography) private var type

    var body: some View {
        Image(systemName: systemName)
            .sageFont(type.caption, weight: .semibold)
            .foregroundStyle(.secondary)
            .frame(width: 16, height: 16)
            .padding(.top, 2)
            .accessibilityHidden(true)
    }
}

