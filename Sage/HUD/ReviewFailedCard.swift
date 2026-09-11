//
//  ReviewFailedCard.swift
//  Sage
//

import SwiftUI

struct ReviewFailedCard: View {
    @Environment(\.sageTypography) private var type
    let message: String
    /// Bind Return / Escape only when no other surface (e.g. the composer) owns them.
    var bindsReturnShortcut: Bool = true
    var onRetry: () -> Void
    var onAccept: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SageDesign.Spacing.small) {
            HStack(spacing: SageDesign.Spacing.small) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .sageFont(type.body, weight: .semibold)
                    .foregroundStyle(SageDesign.Palette.warning)
                Text("Review failed")
                    .sageFont(type.body, weight: .semibold)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityAddTraits(.isHeader)

            Text(message)
                .sageFont(type.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: SageDesign.Spacing.small) {
                Button("Use this reply", action: onAccept)
                    .sageShortcut(.cancelAction, enabled: bindsReturnShortcut)
                    .buttonStyle(.glass)
                    .controlSize(.regular)

                Spacer(minLength: 0)

                Button("Retry review", action: onRetry)
                    .sageShortcut(.defaultAction, enabled: bindsReturnShortcut)
                    .buttonStyle(.glassProminent)
                    .controlSize(.regular)
            }
            .padding(.top, SageDesign.Spacing.extraSmall)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sageGlassCard()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Review failed")
    }
}
