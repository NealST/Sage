//
//  UnifiedDiffView.swift
//  Sage
//

import SwiftUI

/// Compact unified diff (red delete / green insert) for write-file previews.
struct UnifiedDiffView: View {
    let before: String?
    let after: String
    var created: Bool = false
    var truncated: Bool = false
    var path: String?
    /// Prefer payload stats when before/after were clipped for storage.
    var statsOverride: LineDiff.Stats?
    /// Collapsed height budget (line count) before “Show more”.
    var collapsedLineLimit: Int = 24

    @Environment(\.pathGuardPolicy) private var pathGuardPolicy
    @State private var expanded = false

    private var ops: [LineDiff.Operation] {
        let prior = created ? "" : (before ?? "")
        return LineDiff.withCollapsedContext(LineDiff.diff(before: prior, after: after), context: 3)
    }

    private var trueStats: LineDiff.Stats {
        if let statsOverride { return statsOverride }
        let prior = created ? "" : (before ?? "")
        return LineDiff.stats(before: prior, after: after)
    }

    private var displayOps: [LineDiff.Operation] {
        if expanded || ops.count <= collapsedLineLimit { return ops }
        return Array(ops.prefix(collapsedLineLimit))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SageDesign.Spacing.small) {
            HStack(spacing: 6) {
                if let path {
                    Image(systemName: created ? "doc.badge.plus" : "doc.text")
                        .font(.system(size: SageDesign.Typography.iconSize, weight: .semibold))
                    Text(PathTextSupport.attributedString(from: path, policy: pathGuardPolicy))
                        .font(.system(size: SageDesign.Typography.captionSize, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                Text(headerLabel)
                    .font(.system(size: SageDesign.Typography.microSize, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)

            if created, before == nil || before?.isEmpty == true {
                // Pure create — show after as insertions without a confusing empty left side.
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(displayOps.enumerated()), id: \.offset) { _, operation in
                        diffRow(operation)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .padding(.horizontal, 8)
            } else if before == nil, !created {
                Text("Previous contents unavailable (binary or unreadable). Showing proposed file.")
                    .font(.system(size: SageDesign.Typography.microSize))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 12)
                MarkdownContentView(
                    markdown: ToolCallPresentation.fencedMarkdown(
                        content: after,
                        language: path.flatMap(ToolCallPresentation.language(forPath:))
                    )
                )
                .padding(.horizontal, 8)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(displayOps.enumerated()), id: \.offset) { _, operation in
                        diffRow(operation)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .padding(.horizontal, 8)
            }

            if truncated {
                Text("Diff preview truncated for size.")
                    .font(.system(size: SageDesign.Typography.microSize))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 12)
            }

            if ops.count > collapsedLineLimit {
                Button(expanded ? "Show less" : "Show \(ops.count - collapsedLineLimit) more lines") {
                    withAnimation(SageDesign.Motion.expandAnimation) {
                        expanded.toggle()
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: SageDesign.Typography.microSize, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
            }
        }
    }

    private var headerLabel: String {
        if created { return "new file · \(trueStats.insertions) lines" }
        if trueStats.isIdentity { return "no changes" }
        return trueStats.summary
    }

    @ViewBuilder
    private func diffRow(_ operation: LineDiff.Operation) -> some View {
        switch operation {
        case let .equal(line):
            textRow(prefix: " ", text: line, color: .primary.opacity(0.55), fill: Color.clear)

        case let .insert(line):
            textRow(
                prefix: "+",
                text: line,
                color: Color(nsColor: .systemGreen),
                fill: Color(nsColor: .systemGreen).opacity(SageDesign.Chrome.fillOpacity)
            )

        case let .delete(line):
            textRow(
                prefix: "−",
                text: line,
                color: Color(nsColor: .systemRed),
                fill: Color(nsColor: .systemRed).opacity(SageDesign.Chrome.fillOpacity)
            )
        }
    }

    private func textRow(prefix: String, text: String, color: Color, fill: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(prefix)
                .font(.system(size: SageDesign.Typography.captionSize, weight: .semibold, design: .monospaced))
                .foregroundStyle(color.opacity(0.85))
                .frame(width: 14, alignment: .center)
            Text(text.isEmpty ? " " : text)
                .font(.system(size: SageDesign.Typography.captionSize, design: .monospaced))
                .foregroundStyle(color)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 1)
        .background(fill)
    }
}
