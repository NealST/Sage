//
//  SkillTipRows.swift
//  Sage
//

import SwiftUI

struct SkillSaveTipRow: View {
    let suggestion: SkillSuggestion
    let projectDisplayName: String
    @Binding var selectedScope: SkillScope?
    var onSave: (SkillSuggestion) -> Void
    var onDismiss: () -> Void

    @Environment(\.sageTypography) private var type

    private var resolvedScope: SkillScope {
        selectedScope ?? .project
    }

    var body: some View {
        SkillTipChrome.row {
            HStack(alignment: .top, spacing: SageDesign.Spacing.sm) {
                SkillTipChrome.icon(SageDesign.Symbol.skills)

                VStack(alignment: .leading, spacing: SageDesign.Spacing.sm) {
                    HStack(alignment: .top, spacing: SageDesign.Spacing.sm) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(bannerTitle)
                                .font(.system(size: type.caption, weight: .medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            Text(suggestion.skillDescription)
                                .font(.system(size: type.micro))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }

                        Spacer(minLength: SageDesign.Spacing.sm)

                        Button(saveButtonTitle) {
                            onSave(suggestion.allowsScopeChoice
                                ? suggestion.resolved(scope: resolvedScope)
                                : suggestion)
                        }
                        .font(.system(size: type.micro, weight: .semibold))
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                        .help(saveHelp)
                        .accessibilityLabel(saveButtonTitle)

                        SkillTipChrome.dismissButton(action: onDismiss)
                    }

                    if suggestion.allowsScopeChoice {
                        scopeChooser
                    } else if suggestion.type == .enhance {
                        Text(enhanceScopeCaption)
                            .font(.system(size: SageDesign.Typography.microSize))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    private var scopeChooser: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Save location")
                .font(.system(size: SageDesign.Typography.microSize, weight: .medium))
                .foregroundStyle(.secondary)

            Picker("Save location", selection: Binding(
                get: { resolvedScope },
                set: { selectedScope = $0 }
            )) {
                Text("This Project").tag(SkillScope.project)
                Text("Everywhere").tag(SkillScope.global)
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .labelsHidden()
            .frame(maxWidth: 260)

            Text(scopeConsequence(for: resolvedScope))
                .font(.system(size: SageDesign.Typography.microSize))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
                .animation(SageDesign.Motion.expandAnimation, value: resolvedScope)
        }
        .accessibilityElement(children: .contain)
    }

    private var bannerTitle: String {
        switch suggestion.type {
        case .new: return "Save experience “\(suggestion.skillName)”?"
        case .enhance: return "Update existing experience “\(suggestion.skillName)”?"
        case .merge: return "Merge into “\(suggestion.skillName)”?"
        }
    }

    private var saveButtonTitle: String {
        switch suggestion.type {
        case .new: return "Save"
        case .enhance: return "Update"
        case .merge: return "Merge"
        }
    }

    private var enhanceScopeCaption: String {
        switch suggestion.scope {
        case .global:
            return "Folds this task into the global experience — available in every workspace."

        case .project:
            return "Folds this task into the project experience — only used in “\(projectDisplayName)”."
        }
    }

    private func scopeConsequence(for scope: SkillScope) -> String {
        switch scope {
        case .project: return "Saved in “\(projectDisplayName)” and used only while working there."
        case .global: return "Saved globally and available in every workspace."
        }
    }

    private var saveHelp: String {
        switch suggestion.type {
        case .new:
            return suggestion.allowsScopeChoice
                ? scopeConsequence(for: resolvedScope)
                : "Create a skill from this task"
        case .enhance: return "Update existing experience with knowledge from this task"
        case .merge: return "Merge overlapping skills into one"
        }
    }
}

struct SkillChooseTipRow: View {
    let choice: SkillActivationChoice
    @Environment(AgentSession.self) private var session

    var body: some View {
        SkillTipChrome.row {
            VStack(alignment: .leading, spacing: SageDesign.Spacing.sm) {
                HStack(alignment: .top, spacing: SageDesign.Spacing.sm) {
                    SkillTipChrome.icon(SageDesign.Symbol.skills)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Which skill should Sage use?")
                            .font(.system(size: SageDesign.Typography.captionSize, weight: .medium))
                        Text("Several skills match this request. Choose one to load now.")
                            .font(.system(size: SageDesign.Typography.microSize))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(choice.candidates) { candidate in
                        Button {
                            Task { await session.agent.selectSkillActivation(named: candidate.name) }
                        } label: {
                            HStack(alignment: .top, spacing: SageDesign.Spacing.sm) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(candidate.name)
                                        .font(.system(size: SageDesign.Typography.microSize, weight: .semibold))
                                        .lineLimit(1)
                                    Text(candidate.description)
                                        .font(.system(size: SageDesign.Typography.microSize))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 3)
                                    .accessibilityHidden(true)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(TipCandidateButtonStyle())
                        .accessibilityLabel("Use skill \(candidate.name)")
                    }
                }

                Button {
                    Task { await session.agent.skipSkillActivation() }
                } label: {
                    Text("Continue without a skill")
                        .font(.system(size: SageDesign.Typography.microSize, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 2)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Don’t auto-load any skill. Sage continues with the catalog only.")
            }
        }
        .accessibilityElement(children: .contain)
    }
}

struct SkillConsolidateTipRow: View {
    let suggestion: SkillConsolidateSuggestion
    @Binding var primaryPath: String
    var onMerge: (SkillConsolidateSuggestion) -> Void
    var onDismiss: () -> Void

    private var primary: SkillRecallCandidate? {
        suggestion.candidates.first { $0.path == primaryPath } ?? suggestion.primary
    }

    private var removed: [SkillRecallCandidate] {
        suggestion.candidates.filter { $0.path != primaryPath }
    }

    var body: some View {
        SkillTipChrome.row {
            VStack(alignment: .leading, spacing: SageDesign.Spacing.sm) {
                HStack(alignment: .top, spacing: SageDesign.Spacing.sm) {
                    SkillTipChrome.icon("arrow.triangle.merge")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("These skills look overlapping")
                            .font(.system(size: SageDesign.Typography.captionSize, weight: .medium))
                        Text("Merge into one skill to keep the catalog clear.")
                            .font(.system(size: SageDesign.Typography.microSize))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: SageDesign.Spacing.sm)
                    SkillTipChrome.dismissButton(action: onDismiss)
                }

                if suggestion.candidates.count >= 2 {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Keep")
                            .font(.system(size: SageDesign.Typography.microSize, weight: .medium))
                            .foregroundStyle(.secondary)

                        if suggestion.candidates.count <= 3 {
                            Picker("Keep skill", selection: $primaryPath) {
                                ForEach(suggestion.candidates) { candidate in
                                    Text(candidate.name).tag(candidate.path)
                                }
                            }
                            .pickerStyle(.segmented)
                            .controlSize(.small)
                            .labelsHidden()
                            .frame(maxWidth: 280)
                        } else {
                            Picker("Keep skill", selection: $primaryPath) {
                                ForEach(suggestion.candidates) { candidate in
                                    Text(candidate.name).tag(candidate.path)
                                }
                            }
                            .pickerStyle(.menu)
                            .controlSize(.small)
                        }

                        if let primary {
                            Text(mergeConsequence(keeping: primary, removing: removed))
                                .font(.system(size: SageDesign.Typography.microSize))
                                .foregroundStyle(.tertiary)
                                .fixedSize(horizontal: false, vertical: true)
                                .animation(SageDesign.Motion.expandAnimation, value: primaryPath)
                        }
                    }
                }

                HStack(spacing: SageDesign.Spacing.sm) {
                    Button("Merge") {
                        onMerge(suggestion.resolved(primaryPath: primaryPath))
                    }
                    .font(.system(size: SageDesign.Typography.microSize, weight: .semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    .disabled(primary == nil)
                    .help(primary.map { "Merge into “\($0.name)” and move the others to Trash" } ?? "Merge")

                    Spacer(minLength: 0)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func mergeConsequence(
        keeping primary: SkillRecallCandidate,
        removing others: [SkillRecallCandidate]
    ) -> String {
        if others.isEmpty { return "Keeps “\(primary.name)”." }
        let names = others.map { "“\($0.name)”" }.joined(separator: ", ")
        return "Keeps “\(primary.name)”. Moves \(names) to Trash."
    }
}

struct SkillScheduleTipRow: View {
    let draft: ScheduleDraft
    var conversationWording: String?
    var onSave: (ScheduleDraft) -> Void
    var onDismiss: () -> Void
    var onUpdate: ((inout ScheduleDraft) -> Void) -> Void

    @Environment(\.sageTypography) private var type

    var body: some View {
        SkillTipChrome.row {
            HStack(alignment: .top, spacing: SageDesign.Spacing.sm) {
                SkillTipChrome.icon("clock")

                VStack(alignment: .leading, spacing: SageDesign.Spacing.sm) {
                    HStack(alignment: .top, spacing: SageDesign.Spacing.sm) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Schedule this?")
                                .font(.system(size: type.caption, weight: .medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            Text("\(draft.cadence.shortLabel) · \(draft.scopeLabel)")
                                .font(.system(size: type.micro))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)

                            Text(draft.prompt.isEmpty
                                 ? "Write what Sage should do, or use this conversation."
                                 : draft.prompt)
                                .font(.system(size: type.micro))
                                .foregroundStyle(draft.prompt.isEmpty ? .tertiary : .secondary)
                                .lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityLabel(
                                    draft.prompt.isEmpty
                                        ? "No task yet. \(draft.cadence.shortLabel), \(draft.scopeLabel)"
                                        : "\(draft.prompt), \(draft.cadence.shortLabel), \(draft.scopeLabel)"
                                )
                        }

                        Spacer(minLength: SageDesign.Spacing.sm)

                        Button(draft.runOnceNow ? "Save and run" : "Save") {
                            onSave(draft)
                        }
                        .font(.system(size: type.micro, weight: .semibold))
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                        .disabled(draft.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .help(
                            draft.runOnceNow
                                ? "Save this timetable and run it once now."
                                : "Save this timetable. Sage will run it without opening this chat."
                        )
                        .accessibilityLabel(
                            draft.runOnceNow
                                ? "Save schedule and run once now"
                                : "Save schedule"
                        )

                        SkillTipChrome.dismissButton(action: onDismiss)
                    }

                    if let wording = conversationWording, wording != draft.prompt {
                        Button("Use this conversation") {
                            onUpdate {
                                $0.prompt = wording
                            }
                        }
                        .font(.system(size: type.micro, weight: .medium))
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                        .help("Use your latest request in this chat as the scheduled task.")
                        .accessibilityLabel("Use this conversation as the schedule")
                    }

                    Toggle(isOn: Binding(
                        get: { draft.runOnceNow },
                        set: { value in
                            onUpdate { $0.runOnceNow = value }
                        }
                    )) {
                        Text("Run once now")
                    }
                    .toggleStyle(.checkbox)
                    .font(.system(size: type.micro))
                    .help("Run immediately after save. The timetable still fires at the scheduled time.")
                    .accessibilityLabel("Run once now")
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

struct TipCandidateButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.08 : 0.04))
            )
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
