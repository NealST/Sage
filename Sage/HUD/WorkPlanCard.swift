//
//  WorkPlanCard.swift
//  Sage
//

import SwiftUI

/// Confirms a problem-solving strategy — not a list of tool calls.
struct WorkPlanCard: View {
    let plan: WorkPlan
    var isExecuting: Bool
    var onConfirm: () -> Void
    var onCancel: () -> Void
    var onStop: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: SageDesign.Spacing.sm) {
            Text(plan.intent)
                .font(.system(size: SageDesign.Typography.bodySize, weight: .semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            if !plan.approach.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                MarkdownContentView(
                    markdown: plan.approach,
                    collapsible: true,
                    syntaxHighlighting: false
                )
            }

            if !plan.skillNames.isEmpty {
                Text("Uses \(plan.skillNames.joined(separator: ", "))")
                    .font(.system(size: SageDesign.Typography.captionSize))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let sideEffects = plan.sideEffects, !sideEffects.isEmpty {
                Text(sideEffects)
                    .font(.system(size: SageDesign.Typography.captionSize))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }

            if isExecuting {
                HStack(spacing: SageDesign.Spacing.sm) {
                    Spacer(minLength: 0)
                    if let onStop {
                        Button("Stop", role: .cancel, action: onStop)
                            .keyboardShortcut(.cancelAction)
                            .controlSize(.regular)
                    }
                }
                .padding(.top, SageDesign.Spacing.xs)
            } else {
                HStack(spacing: SageDesign.Spacing.sm) {
                    Button("Cancel", role: .cancel, action: onCancel)
                        .keyboardShortcut(.cancelAction)
                        .controlSize(.regular)

                    Spacer(minLength: 0)

                    Button("Run", action: onConfirm)
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                }
                .padding(.top, SageDesign.Spacing.xs)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Plan")
    }
}
