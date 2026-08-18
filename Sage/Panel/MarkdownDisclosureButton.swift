//
//  MarkdownDisclosureButton.swift
//  Sage
//

import SwiftUI

struct MarkdownDisclosureButton: View {
    let title: String
    let expanded: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: SageDesign.Typography.microSize, weight: .semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .rotationEffect(.degrees(expanded ? 180 : 0))
            }
            .foregroundStyle(.primary.opacity(0.75))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .contentShape(Capsule())
        }
        .buttonStyle(SagePressableChipButtonStyle(emphasized: hovering))
        .onHover { hovering = $0 }
        .animation(SageDesign.Motion.contentCrossFade, value: expanded)
        .help(expanded ? "Collapse" : "Expand")
    }
}
