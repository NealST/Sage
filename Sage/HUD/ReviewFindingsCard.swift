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

    let message: String
    var mode: Mode
    var bindsReturnShortcut: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: SageDesign.Spacing.small) {
            Text(title)
                .font(.system(size: SageDesign.Typography.bodySize, weight: .semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            Text(message)
                .font(.system(size: SageDesign.Typography.captionSize))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            switch mode {
            case .continuing:
                Text("Sage will keep working on these.")
                    .font(.system(size: SageDesign.Typography.captionSize))
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
                Button(secondaryTitle, role: .cancel, action: secondary)
                    .controlSize(.regular)
            }

            Spacer(minLength: 0)

            if bindsReturnShortcut {
                Button(primaryTitle, action: primary)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
            } else {
                Button(primaryTitle, action: primary)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
            }
        }
        .padding(.top, SageDesign.Spacing.extraSmall)
    }
}
