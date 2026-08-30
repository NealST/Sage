//
//  ReviewFailedCard.swift
//  Sage
//

import SwiftUI

struct ReviewFailedCard: View {
    let message: String
    var onRetry: () -> Void
    var onAccept: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SageDesign.Spacing.small) {
            Text("Review failed")
                .font(.system(size: SageDesign.Typography.bodySize, weight: .semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            Text(message)
                .font(.system(size: SageDesign.Typography.captionSize))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: SageDesign.Spacing.small) {
                Button("Use this reply", role: .cancel, action: onAccept)
                    .controlSize(.regular)

                Spacer(minLength: 0)

                Button("Retry review", action: onRetry)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
            }
            .padding(.top, SageDesign.Spacing.extraSmall)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Review failed")
    }
}
