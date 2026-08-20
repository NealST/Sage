//
//  ToolRoundLimitCard.swift
//  Sage
//

import SwiftUI

struct ToolRoundLimitCard: View {
    let currentLimit: Int
    let nextLimit: Int
    var onContinue: () -> Void
    var onFinish: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SageDesign.Spacing.sm) {
            Text("Tool round limit reached")
                .font(.system(size: SageDesign.Typography.bodySize, weight: .semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            Text("Sage used \(currentLimit) tool rounds on this turn. Continue for \(nextLimit - currentLimit) more, or finish and summarize.")
                .font(.system(size: SageDesign.Typography.captionSize))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: SageDesign.Spacing.sm) {
                Button("Finish", role: .cancel, action: onFinish)
                    .keyboardShortcut(.cancelAction)
                    .controlSize(.regular)

                Spacer(minLength: 0)

                Button("Continue", action: onContinue)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
            }
            .padding(.top, SageDesign.Spacing.xs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tool round limit")
    }
}
