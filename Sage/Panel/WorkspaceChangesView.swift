//
//  WorkspaceChangesView.swift
//  Sage
//
//  Completed-turn net file changes. Process write chips stay separate.
//

import SwiftUI

struct WorkspaceChangesView: View {
    let changes: WorkspaceChangeSet

    @Environment(\.pathGuardPolicy) private var pathGuardPolicy
    @Environment(\.sageTypography) private var type
    @State private var expandedIDs: Set<String>

    init(changes: WorkspaceChangeSet) {
        self.changes = changes
        let initial: Set<String>
        if changes.files.count == 1, let only = changes.files.first, only.hasLineDiff {
            initial = [only.id]
        } else {
            initial = []
        }
        _expandedIDs = State(initialValue: initial)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ForEach(Array(changes.files.enumerated()), id: \.element.id) { index, file in
                if index > 0 {
                    Divider()
                        .opacity(SageDesign.Chrome.dividerOpacity)
                        .padding(.leading, 36)
                }
                fileRow(file)
            }
            if changes.opaqueMutationCount > 0 {
                Text(opaqueCaption)
                    .sageMicro(type.micro, weight: .medium)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
        }
        // Same material identity as the other transcript cards (card radius +
        // materialize entrance), without sageGlassCard's extra padding — this
        // view manages its own row insets.
        .sagePanelBackground(cornerRadius: SageDesign.Glass.card)
        .sageGlassMaterialize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(headerAccessibilityLabel)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Changes")
                .sageFont(type.body, weight: .semibold)
                .tracking(-0.2)
            Spacer(minLength: 8)
            Text(headerSummary)
                .sageMicro(type.micro, weight: .medium)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, changes.files.isEmpty ? 10 : 6)
    }

    private var headerSummary: String {
        if changes.files.isEmpty { return "" }
        let noun = changes.files.count == 1 ? "file" : "files"
        let stats = changes.totalStats
        if stats.isIdentity {
            return "\(changes.files.count) \(noun)"
        }
        return "\(changes.files.count) \(noun) · \(stats.summary)"
    }

    private var headerAccessibilityLabel: String {
        let summary = headerSummary
        return summary.isEmpty ? "Changes" : "Changes, \(summary)"
    }

    private var opaqueCaption: String {
        "Some other changes aren’t listed."
    }

    @ViewBuilder
    private func fileRow(_ file: WorkspaceFileChange) -> some View {
        let expanded = expandedIDs.contains(file.id)
        VStack(alignment: .leading, spacing: 0) {
            Button {
                toggle(file)
            } label: {
                fileHeader(file, expanded: expanded)
            }
            .buttonStyle(ToolChipHeaderButtonStyle())
            .disabled(!file.hasLineDiff)
            .accessibilityAddTraits(file.hasLineDiff ? .isButton : [])
            .accessibilityHint(file.hasLineDiff ? (expanded ? "Collapse" : "Show changes") : "")

            if expanded, file.hasLineDiff {
                fileDiff(file)
                    .padding(.bottom, 8)
                    .transition(ToolChipChrome.expandTransition)
            }
        }
    }

    private func fileHeader(_ file: WorkspaceFileChange, expanded: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: file.kind.symbolName)
                .sageFont(type.caption, weight: .semibold)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(PathTextSupport.attributedString(from: file.path, policy: pathGuardPolicy))
                    .sageFont(type.caption)
                    .lineLimit(2)
                    .textSelection(.enabled)
                if let previousPath = file.previousPath {
                    Text("from \(previousPath)")
                        .sageMicro(type.micro, weight: .medium)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Text(file.kind.rowLabel)
                .sageMicro(type.micro, weight: .medium)
                .foregroundStyle(.secondary)
            if !file.stats.isIdentity {
                Text(file.stats.summary)
                    .sageMicro(type.micro, weight: .medium)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            if file.hasLineDiff {
                Image(systemName: "chevron.right")
                    .sageFont(type.icon, weight: .semibold)
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func fileDiff(_ file: WorkspaceFileChange) -> some View {
        if file.kind == .removed, file.before == nil {
            Text("Previous contents weren’t captured.")
                .sageMicro(type.micro, weight: .medium)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
        } else {
            UnifiedDiffView(
                before: file.before,
                after: file.after ?? "",
                created: file.kind == .added,
                truncated: file.truncated,
                path: file.path,
                statsOverride: file.stats,
                showsPathHeader: false
            )
        }
    }

    private func toggle(_ file: WorkspaceFileChange) {
        guard file.hasLineDiff else { return }
        var next = expandedIDs
        if next.contains(file.id) {
            next.remove(file.id)
        } else {
            next.insert(file.id)
        }
        if let animation = SageDesign.Motion.expandAnimation {
            withAnimation(animation) {
                expandedIDs = next
            }
        } else {
            expandedIDs = next
        }
    }
}
