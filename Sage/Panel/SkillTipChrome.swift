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
        SkillTipChromeDismissButton(action: action)
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
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
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

private struct SkillTipChromeDismissButton: View {
    let action: () -> Void
    @Environment(\.sageTypography) private var type

    var body: some View {
        Button("Dismiss", systemImage: "xmark", action: action)
            .labelStyle(.iconOnly)
            .sageFont(type.icon, weight: .bold)
            .foregroundStyle(.secondary)
            .frame(width: 22, height: 22)
            .buttonStyle(.plain)
            .help("Dismiss")
    }
}

