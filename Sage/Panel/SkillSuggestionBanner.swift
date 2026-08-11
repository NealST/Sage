//
//  SkillSuggestionBanner.swift
//  Sage
//
//  Inline tip above the composer when skill extraction finds reusable experience.
//  Apple tip pattern: quiet secondary chrome, plain-text actions, dismissible.
//  New skills in a project use a segmented location choice with consequence copy.
//

import SwiftUI

struct SkillSuggestionBanner: View {
    @Environment(AppState.self) private var appState
    @State private var autoDismissTask: Task<Void, Never>?
    /// Per-suggestion write location (defaults to this project when a choice is offered).
    @State private var scopeByID: [UUID: SkillScope] = [:]

    private var queue: SkillSuggestionQueue {
        appState.agent.skillSuggestionQueue
    }

    private var projectDisplayName: String {
        appState.agent.focusedProject?.name ?? "this project"
    }

    var body: some View {
        if queue.showBanner {
            VStack(spacing: SageDesign.Spacing.xs) {
                ForEach(queue.pendingSuggestions) { suggestion in
                    suggestionRow(suggestion)
                }
            }
            .padding(.horizontal, SageDesign.Spacing.lg)
            .padding(.vertical, SageDesign.Spacing.sm)
            .transition(bannerTransition)
            .onAppear { scheduleAutoDismiss() }
            .onChange(of: queue.pendingSuggestions.count) { _, _ in
                pruneScopeChoices()
                scheduleAutoDismiss()
            }
            .onDisappear { autoDismissTask?.cancel() }
        }
    }

    private var bannerTransition: AnyTransition {
        if AccessibilityPreferences.reduceMotion {
            return .opacity
        }
        // Spatial consistency: enter and exit along the same path (from the composer).
        return .asymmetric(
            insertion: .opacity.combined(with: .move(edge: .bottom)),
            removal: .opacity.combined(with: .move(edge: .bottom))
        )
    }

    @ViewBuilder
    private func suggestionRow(_ suggestion: SkillSuggestion) -> some View {
        HStack(alignment: .top, spacing: SageDesign.Spacing.sm) {
            Image(systemName: SageDesign.Symbol.skills)
                .font(.system(size: SageDesign.Typography.captionSize, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 16)
                .padding(.top, 2)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: SageDesign.Spacing.sm) {
                HStack(alignment: .top, spacing: SageDesign.Spacing.sm) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(bannerTitle(for: suggestion))
                            .font(.system(size: SageDesign.Typography.captionSize, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Text(suggestion.skillDescription)
                            .font(.system(size: SageDesign.Typography.microSize))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    Spacer(minLength: SageDesign.Spacing.sm)

                    Button("Save") {
                        confirmSuggestion(suggestion)
                    }
                    .font(.system(size: SageDesign.Typography.microSize, weight: .semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    .help(saveHelp(for: suggestion))

                    Button {
                        withAnimation(SageDesign.Motion.expandAnimation) {
                            scopeByID[suggestion.id] = nil
                            queue.dismiss(suggestion.id)
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.tertiary)
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Dismiss")
                    .accessibilityLabel("Dismiss suggestion")
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
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(SageDesign.Chrome.fillOpacity))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    Color.primary.opacity(
                        AccessibilityPreferences.increaseContrast
                            ? SageDesign.Chrome.strokeOpacity
                            : 0
                    ),
                    lineWidth: AccessibilityPreferences.increaseContrast ? 1 : 0
                )
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
                .accessibilityLabel(scopeConsequence(for: selected))
        }
        .accessibilityElement(children: .contain)
    }

    private func scopeBinding(for suggestion: SkillSuggestion) -> Binding<SkillScope> {
        Binding(
            get: { selectedScope(for: suggestion) },
            set: { scopeByID[suggestion.id] = $0 }
        )
    }

    private func selectedScope(for suggestion: SkillSuggestion) -> SkillScope {
        scopeByID[suggestion.id] ?? .project
    }

    private func bannerTitle(for suggestion: SkillSuggestion) -> String {
        switch suggestion.type {
        case .new:
            return "Save experience “\(suggestion.skillName)”?"
        case .enhance:
            return "Update skill “\(suggestion.skillName)”?"
        }
    }

    private func enhanceScopeCaption(for scope: SkillScope) -> String {
        switch scope {
        case .global:
            return "Updates the global skill — available in every workspace."
        case .project:
            return "Updates the project skill — only used in “\(projectDisplayName)”."
        }
    }

    private func scopeConsequence(for scope: SkillScope) -> String {
        switch scope {
        case .project:
            return "Saved in “\(projectDisplayName)” and used only while working there."
        case .global:
            return "Saved globally and available in every workspace."
        }
    }

    private func saveHelp(for suggestion: SkillSuggestion) -> String {
        switch suggestion.type {
        case .new:
            if suggestion.allowsScopeChoice {
                return scopeConsequence(for: selectedScope(for: suggestion))
            }
            return "Create a skill from this task"
        case .enhance:
            return enhanceScopeCaption(for: suggestion.scope)
        }
    }

    private func confirmSuggestion(_ suggestion: SkillSuggestion) {
        let resolved: SkillSuggestion
        if suggestion.allowsScopeChoice {
            resolved = suggestion.resolved(scope: selectedScope(for: suggestion))
        } else {
            resolved = suggestion
        }

        withAnimation(SageDesign.Motion.expandAnimation) {
            scopeByID[suggestion.id] = nil
            queue.dismiss(suggestion.id)
        }
        appState.agent.startSkillSuggestionSave(resolved)
    }

    private func pruneScopeChoices() {
        let liveIDs = Set(queue.pendingSuggestions.map(\.id))
        scopeByID = scopeByID.filter { liveIDs.contains($0.key) }
    }

    private func scheduleAutoDismiss() {
        autoDismissTask?.cancel()
        autoDismissTask = Task {
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled else { return }
            withAnimation(SageDesign.Motion.expandAnimation) {
                scopeByID.removeAll()
                queue.dismissAll()
            }
        }
    }
}
