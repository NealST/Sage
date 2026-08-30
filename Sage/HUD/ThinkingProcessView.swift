//
//  ThinkingProcessView.swift
//  Sage
//
//  Process text, not the reply. Disclosure so the answer stays primary.
//

import SwiftUI

struct ThinkingProcessView: View {
    let text: String
    var replyStarted: Bool
    @State private var isExpanded = true

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            Text(text)
                .font(.system(size: SageDesign.Typography.captionSize))
                .foregroundStyle(.tertiary)
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
                    .font(.system(size: SageDesign.Typography.captionSize, weight: .medium))
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
