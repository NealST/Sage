//
//  PlanCardView.swift
//  Sage
//

import SwiftUI

struct PlanCardView: View {
    let plan: AgentPlan
    var isExecuting: Bool
    var onConfirm: () -> Void
    var onCancel: () -> Void
    var onStop: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: SageDesign.Spacing.sm) {
            Text(plan.summary)
                .font(.system(size: SageDesign.Typography.bodySize, weight: .semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(plan.steps.enumerated()), id: \.element.id) { index, step in
                    HStack(alignment: .firstTextBaseline, spacing: SageDesign.Spacing.sm) {
                        statusIcon(step.status)
                            .frame(width: 14, alignment: .center)
                        Text(step.title)
                            .font(.system(size: SageDesign.Typography.captionSize))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(step.title), \(accessibilityStatus(step.status))")

                    if index < plan.steps.count - 1 {
                        Divider()
                            .opacity(SageDesign.Chrome.dividerOpacity)
                            .padding(.leading, 22)
                    }
                }
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
