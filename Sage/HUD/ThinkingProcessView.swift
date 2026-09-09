//
//  ThinkingProcessView.swift
//  Sage
//
//  Process text, not the reply. Disclosure so the answer stays primary.
//

import SwiftUI

struct ThinkingProcessView: View {
    @Environment(\.sageTypography) private var type
    let text: String
    var replyStarted: Bool
    @State private var isExpanded = true

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            Text(text)
                .font(.system(size: type.caption))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)
        } label: {
            HStack(spacing: SageDesign.Spacing.extraSmall) {
                if !replyStarted {
                    ProgressView()
                        .controlSize(.mini)
                }
                Text("Thinking")
                    .font(.system(size: type.caption, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .onChange(of: replyStarted) { _, started in
            if started {
                isExpanded = false
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Thinking")
        .accessibilityValue(text)
    }
}
