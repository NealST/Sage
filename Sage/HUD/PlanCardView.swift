//
//  PlanCardView.swift
//  Sage
//

import SwiftUI

struct PlanCardView: View {
    @Environment(\.sageTypography) private var type
    let plan: AgentPlan
    var isExecuting: Bool
    var bindsReturnShortcut: Bool = true
    var onConfirm: () -> Void
    var onCancel: () -> Void
    var onStop: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: SageDesign.Spacing.small) {
            Text(plan.summary)
                .sageFont(type.body, weight: .semibold)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(plan.steps.enumerated()), id: \.element.id) { index, step in
                    ToolCallView(
                        name: step.toolName,
                        argumentsJSON: step.argumentsJSON,
                        titleOverride: "\(index + 1). \(step.title)",
                        status: step.status,
                        resultContent: step.result,
                        previewAgainstDisk: step.status == .pending || step.status == .running,
                        startExpandedIfFileEdit: !isExecuting && step.status == .pending,
                        highlightsSideEffects: !isExecuting
                    )
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(
                        "Step \(index + 1): \(step.title), \(accessibilityStatus(step.status))"
                    )
                }
            }

            if isExecuting {
                if let onStop {
                    PlanStopRow(bindsShortcuts: bindsReturnShortcut, onStop: onStop)
                }
            } else {
                PlanDecisionRow(
                    onConfirm: onConfirm,
                    onCancel: onCancel,
                    bindsShortcuts: bindsReturnShortcut
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sageGlassCard()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Plan")
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
