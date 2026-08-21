//
//  ToolApprovalCard.swift
//  Sage
//

import SwiftUI

struct ToolApprovalCard: View {
    let title: String
    let toolName: String
    let argumentsJSON: String
    var onAllowOnce: () -> Void
    var onAllowSession: () -> Void
    var onAllowTool: () -> Void
    var onSkip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SageDesign.Spacing.small) {
            Text(title)
                .font(.system(size: SageDesign.Typography.bodySize, weight: .semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            Text(subtitle)
                .font(.system(size: SageDesign.Typography.captionSize))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let preview = commandPreview {
                Text(preview)
                    .font(.system(size: SageDesign.Typography.captionSize, design: .monospaced))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: SageDesign.Spacing.small) {
                Button("Skip", role: .cancel, action: onSkip)
                    .keyboardShortcut(.cancelAction)
                    .controlSize(.regular)

                Spacer(minLength: 0)

                Button("Allow once", action: onAllowOnce)
                    .controlSize(.regular)
            }

            HStack(spacing: SageDesign.Spacing.small) {
                Spacer(minLength: 0)

                Button(toolSessionTitle, action: onAllowTool)
                    .controlSize(.regular)

                Button("Allow this call", action: onAllowSession)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
            }
            .padding(.top, SageDesign.Spacing.extraSmall)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tool approval")
    }

    private var subtitle: String {
        if toolName.hasPrefix("mcp__") {
            return "MCP tools stay gated after the work plan. Allow this exact call, remember this MCP tool for the rest of the task, or skip it."
        }
        return "Shell commands stay gated after the work plan. Allow this exact command, remember any shell for the rest of the task, or skip it."
    }

    private var toolSessionTitle: String {
        toolName.hasPrefix("mcp__") ? "Allow this MCP tool" : "Allow any shell"
    }

    private var commandPreview: String? {
        guard toolName == "run_shell_command" else { return nil }
        guard let data = argumentsJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let command = object["command"] as? String
        else { return nil }
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
