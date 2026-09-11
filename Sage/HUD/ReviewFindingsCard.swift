//
//  ReviewFindingsCard.swift
//  Sage
//
//  Inline review findings. Same density as the work-plan and review-failed cards.
//

import SwiftUI

struct ReviewFindingsCard: View {
    enum Mode {
        case continuing
        case resumeMustFix(onContinue: () -> Void, onKeep: () -> Void)
        case optional(onImprove: () -> Void, onKeep: () -> Void)
    }

    @Environment(\.sageTypography) private var type
    let message: String
    var mode: Mode
    var bindsReturnShortcut: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: SageDesign.Spacing.small) {
            header

            Text(message)
                .sageFont(type.caption, weight: isBlocking ? .medium : .regular)
                .foregroundStyle(isBlocking ? .primary : .secondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            switch mode {
            case .continuing:
                Text("Sage will keep working on these.")
                    .sageFont(type.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

            case .resumeMustFix(let onContinue, let onKeep):
                actionRow(
                    secondaryTitle: "Keep this reply",
                    secondary: onKeep,
                    primaryTitle: "Continue fixing",
                    primary: onContinue
                )

            case .optional(let onImprove, let onKeep):
                actionRow(
                    secondaryTitle: "Keep this reply",
                    secondary: onKeep,
                    primaryTitle: "Improve these",
                    primary: onImprove
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sageGlassCard()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .accessibilityHint(accessibilityHint)
    }

    private var title: String {
        switch mode {
        case .continuing, .resumeMustFix:
            return "Review found issues"

        case .optional:
            return "Review found ways to improve"
        }
    }

    /// Must-fix findings block the reply; optional ones don't. The blocking
    /// variant earns the warning treatment so severity reads at a glance.
    private var isBlocking: Bool {
        if case .optional = mode { return false }
        return true
    }

    @ViewBuilder private var header: some View {
        HStack(spacing: SageDesign.Spacing.small) {
            // Distinct severity vocabulary: triangle for blocking issues,
            // wand for non-blocking improvement suggestions.
            Image(systemName: isBlocking ? "exclamationmark.triangle.fill" : "wand.and.stars")
                .sageFont(type.body, weight: .semibold)
                .foregroundStyle(isBlocking ? SageDesign.Palette.warning : Color.accentColor)
                .accessibilityHidden(true)
            Text(title)
                .sageFont(type.body, weight: .semibold)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityAddTraits(.isHeader)
    }

    private var accessibilityHint: String {
        switch mode {
        case .continuing:
            return "Sage will keep working on these issues"

        case .resumeMustFix:
            return "Continue fixing these issues, or keep this reply"

        case .optional:
            return "Improve these, or keep this reply"
        }
    }

    @ViewBuilder
    private func actionRow(
        secondaryTitle: String?,
        secondary: (() -> Void)?,
        primaryTitle: String,
        primary: @escaping () -> Void
    ) -> some View {
        HStack(spacing: SageDesign.Spacing.small) {
            if let secondaryTitle, let secondary {
                Button(role: .cancel, action: secondary) {
                    Text(secondaryTitle)
                }
                .sageShortcut(.cancelAction, enabled: bindsReturnShortcut)
                .buttonStyle(.glass)
                .controlSize(.regular)
            }

            Spacer(minLength: 0)

            Button(primaryTitle, action: primary)
                .sageShortcut(.defaultAction, enabled: bindsReturnShortcut)
                .buttonStyle(.glassProminent)
                .controlSize(.regular)
        }
        .padding(.top, SageDesign.Spacing.extraSmall)
    }
}
