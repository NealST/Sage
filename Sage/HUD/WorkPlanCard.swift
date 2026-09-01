//
//  WorkPlanCard.swift
//  Sage
//

import SwiftUI

/// Confirms a problem-solving strategy — not a list of tool calls.
struct WorkPlanCard: View {
    let plan: WorkPlan
    var isExecuting: Bool
    var bindsReturnShortcut: Bool = true
    var onConfirm: () -> Void
    var onCancel: () -> Void
    var onStop: (() -> Void)?

    var body: some View {
        WorkPlanCardBody(
            plan: plan,
            actions: isExecuting
                ? .executing(onStop: onStop)
                : .confirm(
                    onConfirm: onConfirm,
                    onCancel: onCancel,
                    bindsReturnShortcut: bindsReturnShortcut
                )
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Plan")
    }
}

/// Same layout as `WorkPlanCard`, redacted with the system placeholder treatment.
struct WorkPlanCardSkeleton: View {
    var body: some View {
        WorkPlanCardBody(plan: .skeletonPlaceholder, actions: .placeholder)
            .redacted(reason: .placeholder)
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Preparing plan")
            .accessibilityAddTraits(.updatesFrequently)
    }
}

private enum WorkPlanCardActions {
    case confirm(onConfirm: () -> Void, onCancel: () -> Void, bindsReturnShortcut: Bool)
    case executing(onStop: (() -> Void)?)
    case placeholder
}

private struct WorkPlanCardBody: View {
    let plan: WorkPlan
    let actions: WorkPlanCardActions

    var body: some View {
        VStack(alignment: .leading, spacing: SageDesign.Spacing.small) {
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

            actionRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var actionRow: some View {
        switch actions {
        case .executing(let onStop):
            HStack(spacing: SageDesign.Spacing.small) {
                Spacer(minLength: 0)
                if let onStop {
                    Button("Stop", role: .cancel, action: onStop)
                        .keyboardShortcut(.cancelAction)
                        .controlSize(.regular)
                }
            }
            .padding(.top, SageDesign.Spacing.extraSmall)

        case .confirm(let onConfirm, let onCancel, let bindsReturnShortcut):
            confirmRow(onConfirm: onConfirm, onCancel: onCancel, shortcuts: bindsReturnShortcut)

        case .placeholder:
            confirmRow(onConfirm: {}, onCancel: {}, shortcuts: false)
        }
    }

    private func confirmRow(
        onConfirm: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        shortcuts: Bool
    ) -> some View {
        HStack(spacing: SageDesign.Spacing.small) {
            if shortcuts {
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .controlSize(.regular)
            } else {
                Button("Cancel", role: .cancel, action: onCancel)
                    .controlSize(.regular)
            }

            Spacer(minLength: 0)

            if shortcuts {
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
}

private extension WorkPlan {
    /// Typical act card: intent, markdown approach, side effects, Cancel / Run.
    static let skeletonPlaceholder = WorkPlan(
        kind: .act,
        intent: "Preparing a plan for this request",
        approach: """
        ## Understanding
        Review the request and what done looks like.

        ## Constraints
        Leave unrelated files and settings alone.

        ## Path
        Inspect first, then make the change and check the result.
        """,
        sideEffects: "May change files on this Mac"
    )
}
