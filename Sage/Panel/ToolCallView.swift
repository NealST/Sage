//
//  ToolCallView.swift
//  Sage
//

import SwiftUI

/// Expandable tool-call chip used in the transcript and plan card.
/// File edits (`write_text_file`) expand to a before/after unified diff when possible.
struct ToolCallView: View {
    let name: String
    let argumentsJSON: String
    var titleOverride: String? = nil
    var status: StepStatus? = nil
    /// Completed tool result (may embed a write-file diff payload).
    var resultContent: String? = nil
    /// Compare proposed content against the file on disk (plan confirmation).
    /// Do not enable for historical transcript chips after the write already landed.
    var previewAgainstDisk: Bool = false
    /// When true (plan awaiting confirmation), start expanded for file edits.
    var startExpandedIfFileEdit: Bool = false

    @Environment(\.pathGuardPolicy) private var pathGuardPolicy
    @State private var expanded: Bool
    /// `nil` = still loading; `.absent` = no file; `.text` / `.unreadable` once loaded.
    @State private var diskState: DiskBeforeState = .pending

    private enum DiskBeforeState: Equatable {
        case pending
        case absent
        case unreadable
        case text(String)
    }

    init(
        name: String,
        argumentsJSON: String,
        titleOverride: String? = nil,
        status: StepStatus? = nil,
        resultContent: String? = nil,
        previewAgainstDisk: Bool = false,
        startExpandedIfFileEdit: Bool = false
    ) {
        self.name = name
        self.argumentsJSON = argumentsJSON
        self.titleOverride = titleOverride
        self.status = status
        self.resultContent = resultContent
        self.previewAgainstDisk = previewAgainstDisk
        self.startExpandedIfFileEdit = startExpandedIfFileEdit
        let model = ToolCallPresentation.model(
            name: name,
            argumentsJSON: argumentsJSON,
            titleOverride: titleOverride
        )
        let shouldExpand: Bool
        if case .fileEdit = model.body, startExpandedIfFileEdit {
            shouldExpand = true
        } else {
            shouldExpand = false
        }
        _expanded = State(initialValue: shouldExpand)
    }

    private var model: ToolCallPresentation.Model {
        ToolCallPresentation.model(
            name: name,
            argumentsJSON: argumentsJSON,
            titleOverride: titleOverride
        )
    }

    private var writePayload: WriteFileDiffPayload? {
        resultContent.flatMap(WriteFileResultCodec.payload(in:))
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if expanded, model.isExpandable {
                previewBody
                    .transition(expandTransition)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(SageDesign.Chrome.pillFillOpacity))
        )
        .overlay {
            if AccessibilityPreferences.increaseContrast {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(SageDesign.Chrome.strokeOpacity), lineWidth: 1)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .environment(\.openURL, PathTextSupport.openURLAction)
        .task(id: diskPreviewTaskID) {
            await loadDiskBeforeIfNeeded()
        }
    }

    private var diskPreviewTaskID: String {
        guard previewAgainstDisk,
              writePayload == nil,
              case let .fileEdit(path, _, _) = model.body
        else { return "" }
        return path
    }

    private var header: some View {
        Button {
            guard model.isExpandable else { return }
            withAnimation(SageDesign.Motion.expandAnimation) {
                expanded.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                if let status {
                    statusIcon(status)
                        .frame(width: 14, alignment: .center)
                } else {
                    Image(systemName: iconName)
                        .font(.system(size: SageDesign.Typography.iconSize, weight: .semibold))
                }

                Text(model.title)
                    .font(.system(size: SageDesign.Typography.microSize, weight: .medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if model.isExpandable {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(ToolCallHeaderButtonStyle())
        .foregroundStyle(.secondary)
        .disabled(!model.isExpandable)
        .accessibilityLabel(expanded ? "Collapse tool call" : "Expand tool call")
        .accessibilityValue(model.title)
        .help(model.isExpandable ? (expanded ? "Hide details" : "Show tool details") : model.title)
        .animation(SageDesign.Motion.expandAnimation, value: expanded)
    }

    @ViewBuilder
    private var previewBody: some View {
        VStack(alignment: .leading, spacing: SageDesign.Spacing.sm) {
            Divider().opacity(SageDesign.Chrome.dividerOpacity)

            switch model.body {
            case let .fileEdit(path, content, language):
                fileEditPreview(path: path, content: content, language: language)
            case let .text(label, value):
                labeledText(label: label, value: value)
            case let .fields(pairs):
                fieldsPreview(pairs)
            case .empty:
                EmptyView()
            }
        }
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private func fileEditPreview(path: String, content: String, language: String?) -> some View {
        if let payload = writePayload {
            UnifiedDiffView(
                before: payload.before,
                after: payload.after,
                created: payload.created,
                truncated: payload.truncated,
                path: payload.path,
                statsOverride: payload.stats
            )
        } else if previewAgainstDisk {
            switch diskState {
            case .pending:
                VStack(alignment: .leading, spacing: SageDesign.Spacing.sm) {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.mini)
                        Text("Comparing with current file…")
                            .font(.system(size: SageDesign.Typography.microSize))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 12)
                    proposedContent(content, language: language)
                }
            case .absent:
                UnifiedDiffView(before: nil, after: content, created: true, path: path)
            case .unreadable:
                UnifiedDiffView(before: nil, after: content, created: false, path: path)
            case let .text(before):
                UnifiedDiffView(before: before, after: content, created: false, path: path)
            }
        } else {
            proposedContent(content, language: language, path: path)
        }
    }

    private func proposedContent(_ content: String, language: String?, path: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: SageDesign.Spacing.sm) {
            if let path {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text")
                        .font(.system(size: SageDesign.Typography.iconSize, weight: .semibold))
                    Text(PathTextSupport.attributedString(from: path))
                        .font(.system(size: SageDesign.Typography.captionSize, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(2)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
            }
            MarkdownContentView(
                markdown: ToolCallPresentation.fencedMarkdown(content: content, language: language)
            )
            .padding(.horizontal, 8)
        }
    }

    private func labeledText(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: SageDesign.Typography.microSize, weight: .semibold))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: SageDesign.Typography.captionSize, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
    }

    private func fieldsPreview(_ pairs: [(key: String, value: String)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(pairs.enumerated()), id: \.offset) { _, pair in
                VStack(alignment: .leading, spacing: 2) {
                    Text(pair.key)
                        .font(.system(size: SageDesign.Typography.microSize, weight: .semibold))
                        .foregroundStyle(.tertiary)
                    Text(PathTextSupport.attributedString(from: pair.value))
                        .font(.system(size: SageDesign.Typography.captionSize, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, 12)
    }

    private var iconName: String {
        switch name {
        case "write_text_file": return "square.and.pencil"
        case "read_text_file": return "doc.text"
        case "run_shell_command": return "terminal"
        case "delete_file": return "trash"
        case "load_skill": return "book.closed"
        case "load_skill_resource": return "doc.text.magnifyingglass"
        case "run_skill_script": return "applescript"
        case "save_skill": return "square.and.arrow.down.on.square"
        default: return SageDesign.Symbol.tools
        }
    }

    @ViewBuilder
    private func statusIcon(_ status: StepStatus) -> some View {
        switch status {
        case .pending:
            Image(systemName: SageDesign.Symbol.stepPending)
                .font(.system(size: SageDesign.Typography.microSize, weight: .regular))
                .foregroundStyle(.tertiary)
        case .running:
            ProgressView()
                .controlSize(.mini)
        case .succeeded:
            Image(systemName: SageDesign.Symbol.stepSuccess)
                .font(.system(size: SageDesign.Typography.microSize, weight: .semibold))
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: SageDesign.Symbol.stepFailed)
                .font(.system(size: SageDesign.Typography.microSize, weight: .semibold))
                .foregroundStyle(.red)
        case .skipped:
            Image(systemName: "minus.circle")
                .font(.system(size: SageDesign.Typography.microSize))
                .foregroundStyle(.tertiary)
        }
    }

    private func loadDiskBeforeIfNeeded() async {
        guard previewAgainstDisk,
              writePayload == nil,
              case let .fileEdit(path, _, _) = model.body
        else { return }
        let policy = pathGuardPolicy
        let state: DiskBeforeState = await Task.detached(priority: .userInitiated) {
            guard let url = try? PathGuard.resolveAllowed(path, policy: policy, access: .read) else { return .absent }
            guard FileManager.default.fileExists(atPath: url.path) else { return .absent }
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                return .text(text)
            }
            return .unreadable
        }.value
        diskState = state
    }
}

private struct ToolCallHeaderButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(
                reduceMotion ? .easeOut(duration: 0.12) : SageDesign.Motion.contentCrossFade,
                value: configuration.isPressed
            )
    }
}
