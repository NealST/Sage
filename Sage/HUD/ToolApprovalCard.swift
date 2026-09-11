//
//  ToolApprovalCard.swift
//  Sage
//

import SwiftUI

struct ToolApprovalCard: View {
    @Environment(\.sageTypography) private var type
    @Environment(\.pathGuardPolicy) private var pathGuardPolicy
    let title: String
    let toolName: String
    let argumentsJSON: String
    var authorizationSummary: String?
    var authorizationPrompt: String?
    /// Approvals queued behind this one — helps decide between Allow once / for task.
    var remainingCount: Int = 0
    /// Bind Return / Escape only when no other surface (e.g. the composer) owns them.
    var bindsReturnShortcut: Bool = true
    var onAllowOnce: () -> Void
    var onAllowSession: () -> Void
    var onAllowTool: () -> Void
    var onSkip: () -> Void

    @State private var alwaysAllowPresented = false
    /// Full-argument disclosure — the Allow decision must be makeable on
    /// unclipped content, not just the 300–600 character preview.
    @State private var showsFullArguments = false

    var body: some View {
        VStack(alignment: .leading, spacing: SageDesign.Spacing.small) {
            Text(title)
                .sageFont(type.body, weight: .semibold)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            Text(subtitle)
                .sageFont(type.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if remainingCount > 0 {
                Label(
                    remainingCount == 1
                        ? "1 more approval in this task"
                        : "\(remainingCount) more approvals in this task",
                    systemImage: "checklist"
                )
                .sageFont(type.caption)
                .foregroundStyle(.secondary)
            }

            if let authorizationSummary, !authorizationSummary.isEmpty {
                Text(authorizationSummary)
                    .sageFont(type.caption, design: .monospaced)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !parameterFields.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(parameterFields.enumerated()), id: \.offset) { _, field in
                        HStack(alignment: .top, spacing: 6) {
                            Text(field.key)
                                .foregroundStyle(.secondary)
                            Text(displayValue(field))
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                                // Paths keep their filename when clipped.
                                .lineLimit(
                                    showsFullArguments
                                        ? nil
                                        : SageDesign.Markdown.approvalPreviewLineLimit
                                )
                                .truncationMode(.middle)
                        }
                    }
                }
                .sageFont(type.caption, design: .monospaced)
                .textSelection(.enabled)

                if previewIsClipped {
                    Button {
                        withAnimation(SageDesign.Motion.expandAnimation) {
                            showsFullArguments.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(showsFullArguments ? "Show less" : "Show full arguments")
                            Image(systemName: "chevron.down")
                                .sageFont(type.icon, weight: .semibold)
                                .rotationEffect(.degrees(showsFullArguments ? 180 : 0))
                        }
                        .sageFont(type.caption, weight: .medium)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    .accessibilityLabel(
                        showsFullArguments
                            ? "Collapse full arguments"
                            : "Show full arguments before allowing"
                    )
                }
            }

            HStack(spacing: SageDesign.Spacing.small) {
                Button(role: .cancel, action: onSkip) {
                    Text("Skip")
                }
                .sageShortcut(.cancelAction, enabled: bindsReturnShortcut)
                .buttonStyle(.glass)
                .controlSize(.regular)

                Spacer(minLength: 0)

                Menu {
                    Button("Always allow this permission…") {
                        alwaysAllowPresented = true
                    }
                } label: {
                    Label("More approval options", systemImage: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .labelStyle(.iconOnly)
                .help("Always allow this permission (asks for confirmation)")
                .accessibilityLabel("More approval options")

                Button("Allow for this task", action: onAllowSession)
                    .buttonStyle(.glass)
                    .controlSize(.regular)

                Button("Allow once", action: onAllowOnce)
                    .sageShortcut(.defaultAction, enabled: bindsReturnShortcut)
                    .buttonStyle(.glassProminent)
                    .controlSize(.regular)
            }
            .padding(.top, SageDesign.Spacing.extraSmall)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sageGlassCard()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tool approval: \(toolName)")
        .confirmationDialog(
            "Always allow this permission?",
            isPresented: $alwaysAllowPresented,
            titleVisibility: .visible
        ) {
            Button("Always Allow", action: onAllowTool)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(alwaysAllowMessage)
        }
    }

    private var subtitle: String {
        let prompt = authorizationPrompt?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let prompt, !prompt.isEmpty {
            return prompt
        }
        return "This tool call needs your approval before it runs."
    }

    private var alwaysAllowMessage: String {
        var message = "Sage will stop asking for this permission and remember it until you revoke it in Settings."
        if let authorizationSummary, !authorizationSummary.isEmpty {
            message += "\n\n\(authorizationSummary)"
        }
        return message
    }

    /// Compact key/value preview of what this call will do, for every gated
    /// tool — not just shell commands. Full arguments stay in the transcript.
    private var parameterFields: [(key: String, value: String)] {
        let args = ToolCallPresentation.decodeArgs(argumentsJSON)
        switch ToolCallPresentation.body(
            name: toolName,
            args: args,
            policy: pathGuardPolicy
        ) {
        case .fileEdit(let path, let content, _):
            return [("path", path), ("content", content)]
        case .text(let label, let value):
            return [(label, value)]
        case .fields(let pairs):
            return pairs.map { ($0.key, $0.value) }
        case .empty:
            return []
        }
    }

    /// Clip limit for a field value (the path row is never clipped).
    private func clipLimit(for key: String) -> Int {
        key == "content"
            ? SageDesign.Markdown.approvalContentClipLimit
            : SageDesign.Markdown.approvalTextClipLimit
    }

    private func displayValue(_ field: (key: String, value: String)) -> String {
        guard !showsFullArguments else { return field.value }
        return previewClip(field.value, limit: clipLimit(for: field.key))
    }

    /// True when any value hit its character clip — drives the disclosure.
    private var previewIsClipped: Bool {
        parameterFields.contains { field in
            field.key != "path" && field.value.count > clipLimit(for: field.key)
        }
    }

    private func previewClip(_ value: String, limit: Int) -> String {
        guard value.count > limit else { return value }
        return String(value.prefix(limit)) + "…"
    }
}
