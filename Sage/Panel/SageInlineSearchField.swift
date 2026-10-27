//
//  SageInlineSearchField.swift
//  Sage
//
//  Shared inline search field — the quiet pill floated above task history
//  and the files browser. Sheet and tab contexts have no toolbar, so both
//  surfaces float this field and let content scroll under it with the soft
//  scroll-edge effect.
//

import SwiftUI

struct SageInlineSearchField: View {
    var prompt: String
    @Binding var text: String

    @Environment(\.sageTypography) private var type
    @FocusState private var focused: Bool
    @State private var hoveringClear = false

    var body: some View {
        HStack(spacing: SageDesign.Spacing.small) {
            Image(systemName: "magnifyingglass")
                .sageFont(type.caption)
                .foregroundStyle(.tertiary)
            TextField(prompt, text: $text)
                .sageFont(type.body)
                .textFieldStyle(.plain)
                .focused($focused)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .sageFont(type.caption)
                        .foregroundStyle(
                            hoveringClear ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary)
                        )
                        .frame(
                            width: SageDesign.Control.iconButton,
                            height: SageDesign.Control.iconButton
                        )
                }
                .buttonStyle(.plain)
                .sageHitSlop(visualSize: SageDesign.Control.iconButton)
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
        // The plain-style field needs a visible focus ring for Full Keyboard
        // Access — the system's dedicated indicator color, not an accent guess.
        .overlay(
            RoundedRectangle(cornerRadius: SageDesign.Glass.chip, style: .continuous)
                .strokeBorder(Color(nsColor: .keyboardFocusIndicatorColor), lineWidth: 1.5)
                .opacity(focused ? 1 : 0)
        )
        // macOS search-field convention: Escape clears the query first.
        .onKeyPress(.escape) {
            guard !text.isEmpty else { return .ignored }
            text = ""
            return .handled
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(prompt)
    }
}
