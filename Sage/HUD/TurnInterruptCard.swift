//
//  TurnInterruptCard.swift
//  Sage
//

import SwiftUI

struct TurnInterruptCard: View {
    let preview: String
    var onQueue: () -> Void
    var onSteer: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SageDesign.Spacing.small) {
            Text("Sage is still working")
                .font(.system(size: SageDesign.Typography.bodySize, weight: .semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            Text(preview)
                .font(.system(size: SageDesign.Typography.captionSize))
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: SageDesign.Spacing.small) {
                Button("Cancel", role: .cancel, action: onCancel)
                    .controlSize(.regular)

                Spacer(minLength: 0)

                Button("Queue", action: onQueue)
                    .controlSize(.regular)

                Button("Correct this turn", action: onSteer)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
            }
            .padding(.top, SageDesign.Spacing.extraSmall)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Choose how to use the new message")
    }
}
