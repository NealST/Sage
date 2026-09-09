//
//  ReviewFailedCard.swift
//  Sage
//

import SwiftUI

struct ReviewFailedCard: View {
    @Environment(\.sageTypography) private var type
    let message: String
    var onRetry: () -> Void
    var onAccept: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SageDesign.Spacing.small) {
            Text("Review failed")
                .font(.system(size: type.body, weight: .semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            Text(message)
                .font(.system(size: type.caption))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: SageDesign.Spacing.small) {
                Button("Use this reply", role: .cancel, action: onAccept)
                    .buttonStyle(.glass)
                    .controlSize(.regular)

                Spacer(minLength: 0)

                Button("Retry review", action: onRetry)
                    .keyboardShortcut(.defaultAction)
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
