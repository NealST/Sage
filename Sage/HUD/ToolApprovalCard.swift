//
//  ToolApprovalCard.swift
//  Sage
//

import SwiftUI

struct ToolApprovalCard: View {
    @Environment(\.sageTypography) private var type
    let title: String
    let toolName: String
    let argumentsJSON: String
    var authorizationSummary: String?
    var authorizationPrompt: String?
    var onAllowOnce: () -> Void
    var onAllowSession: () -> Void
    var onAllowTool: () -> Void
    var onSkip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SageDesign.Spacing.small) {
            Text(title)
                .font(.system(size: type.body, weight: .semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            Text(subtitle)
                .font(.system(size: type.caption))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let authorizationSummary, !authorizationSummary.isEmpty {
                Text(authorizationSummary)
                    .font(.system(size: type.caption, design: .monospaced))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let preview = commandPreview {
                Text(preview)
                    .font(.system(size: type.caption, design: .monospaced))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: SageDesign.Spacing.small) {
                Button("Skip", role: .cancel, action: onSkip)
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.glass)
                    .controlSize(.regular)

                Spacer(minLength: 0)

                Menu {
                    Button("Always allow this permission", action: onAllowTool)
                } label: {
                    Label("More approval options", systemImage: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .labelStyle(.iconOnly)
                .help("Always allow this permission")
                .accessibilityLabel("More approval options")

                Button("Allow once", action: onAllowOnce)
                    .buttonStyle(.glass)
                    .controlSize(.regular)

                Button("Allow for this task", action: onAllowSession)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.glassProminent)
                    .controlSize(.regular)
            }
            .padding(.top, SageDesign.Spacing.extraSmall)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sageGlassCard()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tool approval")
    }

    private var subtitle: String {
        let lead: String
        if let prompt = authorizationPrompt?.trimmingCharacters(in: .whitespacesAndNewlines),
           !prompt.isEmpty {
            lead = prompt
        } else {
            lead = "This call needs permission for a gated action."
        }
        return """
        \(lead) \
        Allow it for this task, once, or choose Always in More.
        """
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
