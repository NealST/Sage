//
//  SkillTipsBanner.swift
//  Sage
//
//  Unified tip UI for save / choose / consolidate above the composer.
//

import AppKit
import SwiftUI

struct SkillTipsBanner: View {
    @Environment(AgentSession.self) private var session
    @Environment(AccessibilitySettings.self) private var accessibility
    @Environment(\.sageTypography) private var type
    @State private var autoDismissTask: Task<Void, Never>?
    @State private var scopeByID: [UUID: SkillScope] = [:]
    @State private var primaryPathByID: [UUID: String] = [:]
    @State private var pointerInsideBanner = false

    private var tips: SkillTipStore { session.skills.tips }

    private var projectDisplayName: String {
        session.agent.state.focusedProject?.name ?? "this project"
    }

    var body: some View {
        if tips.showBanner {
            SkillTipChrome.bannerStack {
                ForEach(tips.items) { item in
                    switch item {
                    case .save(let suggestion):
                        suggestionRow(suggestion)
                    case .choose(let choice):
                        chooseRow(choice)
                    case .consolidate(let suggestion):
                        consolidateRow(suggestion)
                    }
                }
            }
            .onAppear {
                seedPrimaryDefaults()
                scheduleAutoDismiss()
            }
            .onChange(of: tips.revision) { _, _ in
                pruneLocalState()
                seedPrimaryDefaults()
                scheduleAutoDismiss()
            }
            .onHover { pointerInsideBanner = $0 }
            .onDisappear {
                autoDismissTask?.cancel()
                pointerInsideBanner = false
            }
        }
    }

    // MARK: - Save

    @ViewBuilder
    private func suggestionRow(_ suggestion: SkillSuggestion) -> some View {
        SkillTipChrome.row {
            HStack(alignment: .top, spacing: SageDesign.Spacing.sm) {
                SkillTipChrome.icon(SageDesign.Symbol.skills)

                VStack(alignment: .leading, spacing: SageDesign.Spacing.sm) {
                    HStack(alignment: .top, spacing: SageDesign.Spacing.sm) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(bannerTitle(for: suggestion))
                                .font(.system(size: type.caption, weight: .medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            Text(suggestion.skillDescription)
                                .font(.system(size: type.micro))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }

                        Spacer(minLength: SageDesign.Spacing.sm)

                        Button("Save") {
                            confirmSuggestion(suggestion)
                        }
                        .font(.system(size: type.micro, weight: .semibold))
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                        .help(saveHelp(for: suggestion))

                        SkillTipChrome.dismissButton {
                            withAnimation(SageDesign.Motion.expandAnimation) {
                                scopeByID[suggestion.id] = nil
                                tips.dismiss(suggestion.id)
                            }
                        }
                    }

                    if suggestion.allowsScopeChoice {
                        scopeChooser(for: suggestion)
                    } else if suggestion.type == .enhance {
                        Text(enhanceScopeCaption(for: suggestion.scope))
                            .font(.system(size: SageDesign.Typography.microSize))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func scopeChooser(for suggestion: SkillSuggestion) -> some View {
        let selected = selectedScope(for: suggestion)
        VStack(alignment: .leading, spacing: 6) {
            Text("Save location")
                .font(.system(size: SageDesign.Typography.microSize, weight: .medium))
                .foregroundStyle(.secondary)

            Picker("Save location", selection: scopeBinding(for: suggestion)) {
                Text("This Project").tag(SkillScope.project)
                Text("Everywhere").tag(SkillScope.global)
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .labelsHidden()
            .frame(maxWidth: 260)

            Text(scopeConsequence(for: selected))
                .font(.system(size: SageDesign.Typography.microSize))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
                .animation(SageDesign.Motion.expandAnimation, value: selected)
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - Choose

    @ViewBuilder
    private func chooseRow(_ choice: SkillActivationChoice) -> some View {
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

    // MARK: - Consolidate

    @ViewBuilder
    private func consolidateRow(_ suggestion: SkillConsolidateSuggestion) -> some View {
        let primaryPath = selectedPrimaryPath(for: suggestion)
        let primary = suggestion.candidates.first { $0.path == primaryPath } ?? suggestion.primary
        let removed = suggestion.candidates.filter { $0.path != primaryPath }

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
                    SkillTipChrome.dismissButton {
                        withAnimation(SageDesign.Motion.expandAnimation) {
                            primaryPathByID[suggestion.id] = nil
                            tips.dismiss(suggestion.id)
                        }
                    }
                }

                if suggestion.candidates.count >= 2 {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Keep")
                            .font(.system(size: SageDesign.Typography.microSize, weight: .medium))
                            .foregroundStyle(.secondary)

                        if suggestion.candidates.count <= 3 {
                            Picker("Keep skill", selection: primaryBinding(for: suggestion)) {
                                ForEach(suggestion.candidates) { candidate in
                                    Text(candidate.name).tag(candidate.path)
                                }
                            }
                            .pickerStyle(.segmented)
                            .controlSize(.small)
                            .labelsHidden()
                            .frame(maxWidth: 280)
                        } else {
                            Picker("Keep skill", selection: primaryBinding(for: suggestion)) {
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
                        let resolved = suggestion.resolved(primaryPath: primaryPath)
                        withAnimation(SageDesign.Motion.expandAnimation) {
                            primaryPathByID[suggestion.id] = nil
                            tips.dismiss(suggestion.id)
                        }
                        session.skills.startConsolidate(resolved)
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

    // MARK: - Actions / helpers

    private func scopeBinding(for suggestion: SkillSuggestion) -> Binding<SkillScope> {
        Binding(
            get: { selectedScope(for: suggestion) },
            set: { scopeByID[suggestion.id] = $0 }
        )
    }

    private func selectedScope(for suggestion: SkillSuggestion) -> SkillScope {
        scopeByID[suggestion.id] ?? .project
    }

    private func primaryBinding(for suggestion: SkillConsolidateSuggestion) -> Binding<String> {
        Binding(
            get: { selectedPrimaryPath(for: suggestion) },
            set: { primaryPathByID[suggestion.id] = $0 }
        )
    }

    private func selectedPrimaryPath(for suggestion: SkillConsolidateSuggestion) -> String {
        primaryPathByID[suggestion.id] ?? suggestion.primaryPath
    }

    private func bannerTitle(for suggestion: SkillSuggestion) -> String {
        switch suggestion.type {
        case .new: return "Save experience “\(suggestion.skillName)”?"
        case .enhance: return "Update skill “\(suggestion.skillName)”?"
        case .merge: return "Merge into “\(suggestion.skillName)”?"
        }
    }

    private func enhanceScopeCaption(for scope: SkillScope) -> String {
        switch scope {
        case .global: return "Updates the global skill — available in every workspace."
        case .project: return "Updates the project skill — only used in “\(projectDisplayName)”."
        }
    }

    private func scopeConsequence(for scope: SkillScope) -> String {
        switch scope {
        case .project: return "Saved in “\(projectDisplayName)” and used only while working there."
        case .global: return "Saved globally and available in every workspace."
        }
    }

    private func saveHelp(for suggestion: SkillSuggestion) -> String {
        switch suggestion.type {
        case .new:
            return suggestion.allowsScopeChoice
                ? scopeConsequence(for: selectedScope(for: suggestion))
                : "Create a skill from this task"
        case .enhance: return enhanceScopeCaption(for: suggestion.scope)
        case .merge: return "Merge overlapping skills into one"
        }
    }

    private func mergeConsequence(
        keeping primary: SkillRecallCandidate,
        removing others: [SkillRecallCandidate]
    ) -> String {
        if others.isEmpty { return "Keeps “\(primary.name)”." }
        let names = others.map { "“\($0.name)”" }.joined(separator: ", ")
        return "Keeps “\(primary.name)”. Moves \(names) to Trash."
    }

    private func confirmSuggestion(_ suggestion: SkillSuggestion) {
        let resolved = suggestion.allowsScopeChoice
            ? suggestion.resolved(scope: selectedScope(for: suggestion))
            : suggestion
        guard tips.confirmSave(suggestion.id) != nil else { return }
        withAnimation(SageDesign.Motion.expandAnimation) {
            scopeByID[suggestion.id] = nil
        }
        session.skills.startSuggestionSave(resolved)
    }

    private func seedPrimaryDefaults() {
        for item in tips.items {
            guard case .consolidate(let suggestion) = item else { continue }
            if primaryPathByID[suggestion.id] == nil {
                primaryPathByID[suggestion.id] = suggestion.primaryPath
            }
        }
    }

    private func pruneLocalState() {
        let liveIDs = Set(tips.items.map(\.id))
        scopeByID = scopeByID.filter { liveIDs.contains($0.key) }
        primaryPathByID = primaryPathByID.filter { liveIDs.contains($0.key) }
    }

    private func scheduleAutoDismiss() {
        autoDismissTask?.cancel()
        guard tips.choosePrompt == nil else { return }
        autoDismissTask = Task {
            // Accumulate 20s of “idle” time; pause while hovered or VoiceOver is on.
            var waited: TimeInterval = 0
            while waited < 20 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                if pointerInsideBanner || accessibility.voiceOverEnabled {
                    continue
                }
                waited += 1
            }
            guard !Task.isCancelled else { return }
            NSAccessibility.post(
                element: NSApp as Any,
                notification: .announcementRequested,
                userInfo: [
                    .announcementKey: "Skill suggestion dismissed",
                    .priorityKey: NSAccessibilityPriorityLevel.medium.rawValue,
                ]
            )
            withAnimation(SageDesign.Motion.expandAnimation) {
                scopeByID.removeAll()
                primaryPathByID.removeAll()
                tips.dismissAutoDismissable()
            }
        }
    }
}

private struct TipCandidateButtonStyle: ButtonStyle {
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
