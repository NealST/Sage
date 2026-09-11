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
    /// Hide the path row when the parent already named the file.
    var showsPathHeader: Bool = true

    @Environment(\.pathGuardPolicy) private var pathGuardPolicy
    @Environment(\.sageTypography) private var type
    @State private var expanded = false
    /// Myers diff is the expensive step and body re-evaluates on every parent
    /// render (streaming ticks, expand toggles), so cache ops+stats by input.
    @State private var diffCache: DiffCache?

    private struct DiffKey: Equatable {
        let before: String?
        let after: String
        let created: Bool
        let statsOverride: LineDiff.Stats?
    }

    private struct DiffCache {
        let key: DiffKey
        let ops: [LineDiff.Operation]
        let stats: LineDiff.Stats
    }

    private var diffKey: DiffKey {
        DiffKey(before: before, after: after, created: created, statsOverride: statsOverride)
    }

    /// Cached value only when it matches the current inputs — body must never
    /// compute the diff itself (large edits would stall streaming layout).
    private var validCache: DiffCache? {
        guard let diffCache, diffCache.key == diffKey else { return nil }
        return diffCache
    }

    private static func compute(key: DiffKey) -> DiffCache {
        let prior = key.created ? "" : (key.before ?? "")
        let ops = LineDiff.withCollapsedContext(
            LineDiff.diff(before: prior, after: key.after),
            context: 3
        )
        let stats = key.statsOverride ?? LineDiff.stats(before: prior, after: key.after)
        return DiffCache(key: key, ops: ops, stats: stats)
    }

    private func displayOps(_ ops: [LineDiff.Operation]) -> [LineDiff.Operation] {
        if expanded || ops.count <= collapsedLineLimit { return ops }
        var cut = collapsedLineLimit
        // Never end on a dangling delete — its insert pair belongs with it.
        while cut > 1 {
            if case .delete = ops[cut - 1] { cut -= 1 } else { break }
        }
        return Array(ops.prefix(cut))
    }

    var body: some View {
        Group {
            if let diff = validCache {
                diffContent(diff)
            } else {
                Text("Preparing diff…")
                    .sageMicro(type.micro)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 12)
                    .accessibilityLabel("Preparing diff")
            }
        }
        .task(id: diffKey) {
            guard validCache == nil else { return }
            let key = diffKey
            let cache = await Task.detached(priority: .userInitiated) {
                Self.compute(key: key)
            }.value
            // A newer input may have restarted this task while the detached
            // diff was in flight — don't let the stale result overwrite it.
            if !Task.isCancelled {
                diffCache = cache
            }
        }
    }

    private func diffContent(_ diff: DiffCache) -> some View {
        let displayed = displayOps(diff.ops)
        let remaining = diff.ops.count - displayed.count
        return VStack(alignment: .leading, spacing: SageDesign.Spacing.small) {
            if showsPathHeader {
                HStack(spacing: 6) {
                    if let path {
                        Image(systemName: created ? "doc.badge.plus" : "doc.text")
                            .sageFont(type.icon, weight: .semibold)
                        Text(PathTextSupport.attributedString(from: path, policy: pathGuardPolicy))
                            .sageFont(type.caption, design: .monospaced)
                            .textSelection(.enabled)
                            // Middle truncation keeps the filename visible when
                            // deep directory names overflow.
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 0)
                    Text(headerLabel(diff.stats))
                        .sageMicro(type.micro, weight: .medium)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
            }

            if created, before == nil || before?.isEmpty == true {
                // Pure create — show after as insertions without a confusing empty left side.
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(displayed.enumerated()), id: \.offset) { _, operation in
                        diffRow(operation)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .padding(.horizontal, 8)
            } else if before == nil, !created {
                Text("Previous contents unavailable (binary or unreadable). Showing proposed file.")
                    .sageMicro(type.micro)
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
                    ForEach(Array(displayed.enumerated()), id: \.offset) { _, operation in
                        diffRow(operation)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .padding(.horizontal, 8)
            }

            if truncated {
                Text("Diff preview truncated for size.")
                    .sageMicro(type.micro)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 12)
            }

            if diff.ops.count > collapsedLineLimit {
                Button(expanded ? "Show less" : "Show \(remaining) more lines") {
                    withAnimation(SageDesign.Motion.expandAnimation) {
                        expanded.toggle()
                    }
                }
                .buttonStyle(.plain)
                .sageMicro(type.micro, weight: .semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
            }
        }
    }

    private func headerLabel(_ stats: LineDiff.Stats) -> String {
        if created { return "new file · \(stats.insertions) lines" }
        if stats.isIdentity { return "no changes" }
        return stats.summary
    }

    @ViewBuilder
    private func diffRow(_ operation: LineDiff.Operation) -> some View {
        switch operation {
        case let .equal(line):
            textRow(prefix: " ", text: line, color: .primary.opacity(0.7), fill: Color.clear)

        case let .insert(line):
            textRow(
                prefix: "+",
                text: line,
                color: SageDesign.Palette.success,
                fill: SageDesign.Palette.success.opacity(SageDesign.Chrome.diffFillOpacity)
            )

        case let .delete(line):
            textRow(
                prefix: "−",
                text: line,
                color: SageDesign.Palette.danger,
                fill: SageDesign.Palette.danger.opacity(SageDesign.Chrome.diffFillOpacity)
            )
        }
    }

    private func textRow(prefix: String, text: String, color: Color, fill: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(prefix)
                .sageFont(type.caption, weight: .semibold, design: .monospaced)
                .foregroundStyle(color.opacity(0.85))
                .frame(width: 14, alignment: .center)
            Text(text.isEmpty ? " " : text)
                .sageFont(type.caption, design: .monospaced)
                .foregroundStyle(color)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 1)
        .background(fill)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Self.rowAccessibilityLabel(prefix: prefix, text: text))
    }

    /// The +/− glyphs are decorative to VoiceOver — speak the change kind instead.
    private static func rowAccessibilityLabel(prefix: String, text: String) -> String {
        let body = text.isEmpty ? "empty line" : text
        switch prefix {
        case "+": return "Added: \(body)"
        case "−": return "Removed: \(body)"
        default: return body
        }
    }
}
