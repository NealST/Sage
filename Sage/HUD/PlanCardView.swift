//
//  PlanCardView.swift
//  Sage
//

import SwiftUI

struct PlanCardView: View {
    let plan: AgentPlan
    var isExecuting: Bool
    var bindsReturnShortcut: Bool = true
    var onConfirm: () -> Void
    var onCancel: () -> Void
    var onStop: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: SageDesign.Spacing.small) {
            Text(plan.summary)
                .font(.system(size: SageDesign.Typography.bodySize, weight: .semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(plan.steps) { step in
                    ToolCallView(
                        name: step.toolName,
                        argumentsJSON: step.argumentsJSON,
                        titleOverride: step.title,
                        status: step.status,
                        resultContent: step.result,
                        previewAgainstDisk: step.status == .pending || step.status == .running,
                        startExpandedIfFileEdit: !isExecuting && step.status == .pending
                    )
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(step.title), \(accessibilityStatus(step.status))")
                }
            }

            if isExecuting {
                HStack(spacing: SageDesign.Spacing.small) {
                    Spacer(minLength: 0)
                    if let onStop {
                        Button("Stop", role: .cancel, action: onStop)
                            .keyboardShortcut(.cancelAction)
                            .controlSize(.regular)
                    }
                }
                .padding(.top, SageDesign.Spacing.extraSmall)
            } else {
                confirmRow
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Plan")
    }

    @ViewBuilder private var confirmRow: some View {
        HStack(spacing: SageDesign.Spacing.small) {
            if bindsReturnShortcut {
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .controlSize(.regular)
            } else {
                Button("Cancel", role: .cancel, action: onCancel)
                    .controlSize(.regular)
            }

            Spacer(minLength: 0)

            if bindsReturnShortcut {
                Button("Run", action: onConfirm)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
            } else {
                Button("Run", action: onConfirm)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
            }
        }
        .padding(.top, SageDesign.Spacing.extraSmall)
    }

    private func accessibilityStatus(_ status: StepStatus) -> String {
        switch status {
        case .pending: return "pending"
        case .running: return "running"
        case .succeeded: return "done"
        case .failed: return "failed"
        case .skipped: return "skipped"
        }
    }
}
