//
//  SageInlineSearchField.swift
//  Sage
//

import SwiftUI

/// Shared inline search field — the quiet pill floated above task history
/// and the files browser. Sheet and tab contexts have no toolbar, so both
/// surfaces float this field and let content scroll under it with the soft
/// scroll-edge effect.
struct SageInlineSearchField: View {
    var prompt: String
    @Binding var text: String

    @Environment(\.sageTypography) private var type
    @State private var hoveringClear = false

    var body: some View {
        HStack(spacing: SageDesign.Spacing.small) {
            Image(systemName: "magnifyingglass")
                .sageFont(type.caption)
                .foregroundStyle(.tertiary)
            TextField(prompt, text: $text)
                .sageFont(type.body)
                .textFieldStyle(.plain)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .sageFont(type.caption)
                        .foregroundStyle(
                            hoveringClear ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary)
                        )
                }
                .buttonStyle(.plain)
                .onHover { hoveringClear = $0 }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, SageDesign.Spacing.medium)
        .padding(.vertical, SageDesign.Spacing.compactChipVertical)
        .background(
            RoundedRectangle(cornerRadius: SageDesign.Glass.chip, style: .continuous)
                .fill(Color.primary.opacity(SageDesign.Chrome.pillFillOpacity))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(prompt)
    }
}
