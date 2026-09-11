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
    /// Long streams show only the live tail so todo/plan cards stay on
    /// screen; the full reasoning is one tap away.
    @State private var showsFullText = false

    /// Glanceable tail length while thinking is live.
    private static let tailLineCount = 12

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: SageDesign.Spacing.extraSmall) {
                Text(showsFullText ? text : tailText)
                    .sageFont(type.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if isLongStream {
                    MarkdownDisclosureButton(
                        title: showsFullText ? "Show recent" : "Show all thinking",
                        expanded: showsFullText,
                        action: {
                            withAnimation(SageDesign.Motion.expandAnimation) {
                                showsFullText.toggle()
                            }
                        }
                    )
                }
            }
            .padding(.top, 2)
        } label: {
            HStack(spacing: SageDesign.Spacing.extraSmall) {
                if !replyStarted {
                    ProgressView()
                        .controlSize(.mini)
                }
                Text("Thinking")
                    .sageFont(type.caption, weight: .medium)
                    .foregroundStyle(.secondary)
            }
        }
        .onChange(of: replyStarted) { _, started in
            if started {
                withAnimation(SageDesign.Motion.expandAnimation) {
                    isExpanded = false
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Thinking")
        .accessibilityValue(summarizedThinking)
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var lines: [Substring] {
        text.split(separator: "\n", omittingEmptySubsequences: false)
    }

    private var isLongStream: Bool {
        lines.count > Self.tailLineCount
    }

    private var tailText: String {
        let tail = lines.suffix(Self.tailLineCount).joined(separator: "\n")
        return isLongStream ? "…\n\(tail)" : tail
    }

    /// Whole-stream values re-announce everything on each poll tick — keep it short.
    private var summarizedThinking: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Waiting for first thoughts…" }
        if trimmed.count <= 140 { return trimmed }
        return "\(trimmed.prefix(140))…"
    }
}
