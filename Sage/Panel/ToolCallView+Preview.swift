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

    func proposedContent(_ content: String, language: String?, path: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: SageDesign.Spacing.small) {
            if let path {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text")
                        .font(.system(size: SageDesign.Typography.iconSize, weight: .semibold))
                    Text(PathTextSupport.attributedString(from: path, policy: pathGuardPolicy))
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

    func labeledText(label: String, value: String) -> some View {
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

    func fieldsPreview(_ pairs: [(key: String, value: String)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(pairs.enumerated()), id: \.offset) { _, pair in
                VStack(alignment: .leading, spacing: 2) {
                    Text(pair.key)
                        .font(.system(size: SageDesign.Typography.microSize, weight: .semibold))
                        .foregroundStyle(.tertiary)
                    Text(PathTextSupport.attributedString(from: pair.value, policy: pathGuardPolicy))
                        .font(.system(size: SageDesign.Typography.captionSize, design: .monospaced))
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

    @ViewBuilder
    func statusIcon(_ status: StepStatus) -> some View {
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

struct ToolCallHeaderButtonStyle: ButtonStyle {
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
