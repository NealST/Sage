//
//  ToolRoundLimitCard.swift
//  Sage
//

import SwiftUI

struct ToolRoundLimitCard: View {
    @Environment(\.sageTypography) private var type
    let currentLimit: Int
    let nextLimit: Int
    /// Bind Return / Escape only when no other surface (e.g. the composer) owns them.
    var bindsReturnShortcut: Bool = true
    var onContinue: () -> Void
    var onFinish: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SageDesign.Spacing.small) {
            Text("Tool round limit reached")
                .sageFont(type.body, weight: .semibold)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            Text("""
            Sage used \(currentLimit) tool rounds on this turn. Continue for \
            \(nextLimit - currentLimit) more, or finish and summarize.
            """)
                .sageFont(type.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: SageDesign.Spacing.small) {
                Button("Finish", role: .cancel, action: onFinish)
                    .sageShortcut(.cancelAction, enabled: bindsReturnShortcut)
                    .buttonStyle(.glass)
                    .controlSize(.regular)

                Spacer(minLength: 0)

                Button("Continue", action: onContinue)
                    .sageShortcut(.defaultAction, enabled: bindsReturnShortcut)
                    .buttonStyle(.glassProminent)
                    .controlSize(.regular)
            }
            .padding(.top, SageDesign.Spacing.extraSmall)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sageGlassCard()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tool round limit")
    }
}
