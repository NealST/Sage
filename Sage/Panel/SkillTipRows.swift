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
            HStack(alignment: .top, spacing: SageDesign.Spacing.small) {
                SkillTipChrome.icon(SageDesign.Symbol.skills)

                VStack(alignment: .leading, spacing: SageDesign.Spacing.small) {
                    HStack(alignment: .top, spacing: SageDesign.Spacing.small) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(bannerTitle)
                                .sageFont(type.caption, weight: .medium)
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            Text(suggestion.skillDescription)
                                .sageFont(type.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }

                        Spacer(minLength: SageDesign.Spacing.small)

                        Button(saveButtonTitle) {
                            onSave(suggestion.allowsScopeChoice
                                ? suggestion.resolved(scope: resolvedScope)
                                : suggestion)
                        }
                        .sageMicro(type.micro, weight: .semibold)
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
                            .sageFont(type.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var scopeChooser: some View {
        VStack(alignment: .leading, spacing: SageDesign.Spacing.labelGap) {
            Text("Save location")
                .sageMicro(type.micro, weight: .medium)
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
                .sageFont(type.caption)
                .foregroundStyle(.secondary)
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
            return "Folds this task into the global experience, available in every workspace."

        case .project:
            return "Folds this task into the project experience, only used in “\(projectDisplayName)”."
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

        case .enhance:
            return "Update existing experience with knowledge from this task"

        case .merge:
            return "Merge overlapping skills into one"
        }
    }
}

struct SkillChooseTipRow: View {
    let choice: SkillActivationChoice
    @Environment(AgentSession.self) private var session
    @Environment(\.sageTypography) private var type

    var body: some View {
        SkillTipChrome.row {
            VStack(alignment: .leading, spacing: SageDesign.Spacing.small) {
                HStack(alignment: .top, spacing: SageDesign.Spacing.small) {
                    SkillTipChrome.icon(SageDesign.Symbol.skills)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Which skill should Sage use?")
                            .sageFont(type.caption, weight: .medium)
                        Text("Several skills match this request. Choose one to load now.")
                            .sageFont(type.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }

                VStack(alignment: .leading, spacing: SageDesign.Spacing.extraSmall) {
                    ForEach(choice.candidates) { candidate in
                        Button {
                            Task { await session.agent.selectSkillActivation(named: candidate.name) }
                        } label: {
                            HStack(alignment: .top, spacing: SageDesign.Spacing.small) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(candidate.name)
                                        .sageFont(type.caption, weight: .medium)
                                        .lineLimit(1)
                                    Text(candidate.description)
                                        .sageFont(type.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .sageFont(type.icon, weight: .semibold)
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 3)
                                    .accessibilityHidden(true)
                            }
                            .padding(.horizontal, SageDesign.Spacing.chipHorizontal)
                            .padding(.vertical, SageDesign.Spacing.chipVertical)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(SagePlainActionButtonStyle())
                        .accessibilityLabel("Use skill \(candidate.name)")
                    }
                }

                Button {
                    Task { await session.agent.skipSkillActivation() }
                } label: {
                    Text("Continue without a skill")
                        .sageMicro(type.micro, weight: .medium)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, SageDesign.Spacing.compactChipHorizontal)
                        .padding(.vertical, SageDesign.Spacing.compactChipVertical)
                        .contentShape(Rectangle())
                }
                .buttonStyle(SagePlainActionButtonStyle())
                .help("Don’t auto-load any skill. Sage continues with the catalog only.")
            }
        }
        .accessibilityElement(children: .contain)
    }
}
