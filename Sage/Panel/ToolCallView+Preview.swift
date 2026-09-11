//
//  ToolCallView+Preview.swift
//  Sage
//

import SwiftUI

extension ToolCallView {
    @ViewBuilder
    func fileEditPreview(path: String, content: String, language: String?) -> some View {
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
                VStack(alignment: .leading, spacing: SageDesign.Spacing.small) {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.mini)
                        Text("Comparing with current file…")
                            .sageMicro(type.micro)
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

    func proposedContent(_ content: String, language: String?, path: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: SageDesign.Spacing.small) {
            if let path {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text")
                        .sageFont(type.icon, weight: .semibold)
                    Text(PathTextSupport.attributedString(from: path, policy: pathGuardPolicy))
                        .sageFont(type.caption, design: .monospaced)
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .truncationMode(.middle)
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

    func labeledText(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .sageMicro(type.micro, weight: .semibold)
                .foregroundStyle(.tertiary)
            Text(value)
                .sageFont(type.caption, design: .monospaced)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
    }

    func fieldsPreview(_ pairs: [(key: String, value: String)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(pairs.enumerated()), id: \.offset) { _, pair in
                VStack(alignment: .leading, spacing: 2) {
                    Text(pair.key)
                        .sageMicro(type.micro, weight: .semibold)
                        .foregroundStyle(.tertiary)
                    Text(PathTextSupport.attributedString(from: pair.value, policy: pathGuardPolicy))
                        .sageFont(type.caption, design: .monospaced)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, 12)
    }

    var iconName: String {
        switch name {
        case "write_text_file": return "square.and.pencil"
        case "read_text_file": return "doc.text"
        case "run_shell_command": return "terminal"
        case "delete_file": return "trash"
        case "load_skill": return "book.closed"
        case "load_skill_resource": return "doc.text.magnifyingglass"
        case "run_skill_script": return "applescript"
        case "save_skill": return "square.and.arrow.down.on.square"
        case "recall_task_transcript": return "clock.arrow.circlepath"
        default: return SageDesign.Symbol.tools
        }
    }

    /// Status flips are causal moments — the symbol reacts on the frame they
    /// land. Bounce celebrates completion, pulse flags failure; both are
    /// dropped under Reduce Motion.
    @ViewBuilder
    func statusIcon(_ status: StepStatus) -> some View {
        switch status {
        case .pending:
            Image(systemName: SageDesign.Symbol.stepPending)
                .sageMicro(type.micro, weight: .regular)
                .foregroundStyle(.tertiary)

        case .running:
            ProgressView()
                .controlSize(.mini)

        case .succeeded:
            Image(systemName: SageDesign.Symbol.stepSuccess)
                .sageMicro(type.micro, weight: .semibold)
                .foregroundStyle(SageDesign.Palette.success)
                .sageSymbolEffect(.bounce, value: status)

        case .failed:
            Image(systemName: SageDesign.Symbol.stepFailed)
                .sageMicro(type.micro, weight: .semibold)
                .foregroundStyle(SageDesign.Palette.danger)
                .sageSymbolEffect(.pulse, value: status)

        case .skipped:
            Image(systemName: "minus.circle")
                .sageMicro(type.micro)
                .foregroundStyle(.tertiary)
        }
    }

    func loadDiskBeforeIfNeeded() async {
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
