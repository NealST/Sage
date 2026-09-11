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
    /// Shared identity with `WorkPlanCardSkeleton` so the glass material
    /// morphs when the reserved skeleton becomes the confirmable card.
    var matchedGlass: SageDesign.Glass.MatchedSpec? = nil
    var onConfirm: () -> Void
    var onCancel: () -> Void
    var onStop: (() -> Void)?

    var body: some View {
        WorkPlanCardBody(
            plan: plan,
            actions: isExecuting
                ? .executing(onStop: onStop, bindsReturnShortcut: bindsReturnShortcut)
                : .confirm(
                    onConfirm: onConfirm,
                    onCancel: onCancel,
                    bindsReturnShortcut: bindsReturnShortcut
                ),
            matchedGlass: matchedGlass
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Plan")
    }
}

/// Same layout as `WorkPlanCard`, redacted with the system placeholder treatment.
struct WorkPlanCardSkeleton: View {
    var matchedGlass: SageDesign.Glass.MatchedSpec? = nil

    var body: some View {
        WorkPlanCardBody(plan: .skeletonPlaceholder, actions: .placeholder, matchedGlass: matchedGlass)
            .redacted(reason: .placeholder)
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Preparing plan")
            .accessibilityAddTraits(.updatesFrequently)
    }
}

private enum WorkPlanCardActions {
    case confirm(onConfirm: () -> Void, onCancel: () -> Void, bindsReturnShortcut: Bool)
    case executing(onStop: (() -> Void)?, bindsReturnShortcut: Bool)
    case placeholder
}

private struct WorkPlanCardBody: View {
    @Environment(\.sageTypography) private var type
    let plan: WorkPlan
    let actions: WorkPlanCardActions
    var matchedGlass: SageDesign.Glass.MatchedSpec? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: SageDesign.Spacing.small) {
            Text(plan.intent)
                .sageFont(type.body, weight: .semibold)
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
                    .sageFont(type.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let sideEffects = plan.sideEffects,
               !sideEffects.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Label {
                    Text(sideEffects)
                        .sageFont(type.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .sageFont(type.icon, weight: .semibold)
                        .foregroundStyle(SageDesign.Palette.warning)
                }
                .padding(SageDesign.Spacing.extraSmall)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: SageDesign.Glass.chip, style: .continuous)
                        .fill(SageDesign.Palette.warning.opacity(SageDesign.Chrome.diffFillOpacity))
                )
                .accessibilityLabel("Side effects: \(sideEffects)")
                .padding(.top, SageDesign.Spacing.extraSmall)
            }

            actionRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sageGlassCard(matched: matchedGlass)
    }

    @ViewBuilder private var actionRow: some View {
        switch actions {
        case .executing(let onStop, let bindsReturnShortcut):
            if let onStop {
                PlanStopRow(bindsShortcuts: bindsReturnShortcut, onStop: onStop)
            }

        case .confirm(let onConfirm, let onCancel, let bindsReturnShortcut):
            PlanDecisionRow(
                onConfirm: onConfirm,
                onCancel: onCancel,
                bindsShortcuts: bindsReturnShortcut
            )

        case .placeholder:
            PlanDecisionRow(onConfirm: {}, onCancel: {}, bindsShortcuts: false)
        }
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
