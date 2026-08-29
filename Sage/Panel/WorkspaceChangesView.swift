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
                    .font(.system(size: SageDesign.Typography.microSize))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(SageDesign.Chrome.pillFillOpacity))
        )
        .overlay {
            if AccessibilityPreferences.increaseContrast {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(SageDesign.Chrome.strokeOpacity), lineWidth: 1)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(headerAccessibilityLabel)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Changes")
                .font(.system(size: SageDesign.Typography.bodySize, weight: .semibold))
                .tracking(-0.2)
            Spacer(minLength: 8)
            Text(headerSummary)
                .font(.system(size: SageDesign.Typography.microSize, weight: .medium))
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
            .buttonStyle(WorkspaceChangePressStyle())
            .disabled(!file.hasLineDiff)
            .accessibilityAddTraits(file.hasLineDiff ? .isButton : [])
            .accessibilityHint(file.hasLineDiff ? (expanded ? "Collapse" : "Show changes") : "")

            if expanded, file.hasLineDiff {
                fileDiff(file)
                    .padding(.bottom, 8)
                    .transition(expandTransition)
            }
        }
    }

    private func fileHeader(_ file: WorkspaceFileChange, expanded: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: file.kind.symbolName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(PathTextSupport.attributedString(from: file.path, policy: pathGuardPolicy))
                    .font(.system(size: SageDesign.Typography.captionSize))
                    .lineLimit(2)
                    .textSelection(.enabled)
                if let previousPath = file.previousPath {
                    Text("from \(previousPath)")
                        .font(.system(size: SageDesign.Typography.microSize))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Text(file.kind.rowLabel)
                .font(.system(size: SageDesign.Typography.microSize, weight: .medium))
                .foregroundStyle(.secondary)
            if !file.stats.isIdentity {
                Text(file.stats.summary)
                    .font(.system(size: SageDesign.Typography.microSize, weight: .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            if file.hasLineDiff {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
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
                .font(.system(size: SageDesign.Typography.microSize))
                .foregroundStyle(.tertiary)
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

    private var expandTransition: AnyTransition {
        if AccessibilityPreferences.reduceMotion {
            return .opacity
        }
        return .asymmetric(
            insertion: .opacity.combined(with: .move(edge: .top)),
            removal: .opacity
        )
    }
}

private struct WorkspaceChangePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.55 : 1)
            .animation(
                AccessibilityPreferences.reduceMotion
                    ? nil
                    : .easeOut(duration: 0.1),
                value: configuration.isPressed
            )
    }
}
