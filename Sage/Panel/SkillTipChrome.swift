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
        Image(systemName: systemName)
            .font(.system(size: SageDesign.Typography.captionSize, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 16, height: 16)
            .padding(.top, 2)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    static func dismissButton(action: @escaping () -> Void) -> some View {
        Button("Dismiss", systemImage: "xmark", action: action)
            .labelStyle(.iconOnly)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.secondary)
            .frame(width: 22, height: 22)
            .buttonStyle(.plain)
            .help("Dismiss")
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
            .sagePanelBackground(cornerRadius: 10, weight: .clear)
            .sageGlassMaterialize()
    }
}

