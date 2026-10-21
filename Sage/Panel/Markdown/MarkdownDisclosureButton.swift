//
//  MarkdownDisclosureButton.swift
//  Sage
//

import SwiftUI

struct MarkdownDisclosureButton: View {
    let title: String
    let expanded: Bool
    let action: () -> Void

    @Environment(\.sageTypography) private var type
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: SageDesign.Spacing.extraSmall) {
                Text(title)
                    .sageMicro(type.micro, weight: .semibold)
                Image(systemName: "chevron.down")
                    .sageFont(type.icon, weight: .semibold)
                    .rotationEffect(.degrees(expanded ? 180 : 0))
            }
            .foregroundStyle(.primary.opacity(SageDesign.Chrome.deemphasizedContentOpacity))
            .padding(.horizontal, SageDesign.Spacing.compactChipHorizontal + SageDesign.Spacing.extraSmall)
            .padding(.vertical, SageDesign.Spacing.compactChipVertical + SageDesign.Spacing.extraSmall)
            .contentShape(Capsule())
        }
        .buttonStyle(SagePressableChipButtonStyle(emphasized: hovering))
        .onHover { hovering = $0 }
        // Same spring as the content it expands, so chevron and height
        // settle together instead of at two tempos.
        .animation(SageDesign.Motion.expandAnimation, value: expanded)
        .help(expanded ? "Collapse" : "Expand")
    }
}
