//
//  SkillSuggestionBanner.swift
//  Sage
//
//  Inline banner displayed above the composer when skill extraction identifies
//  reusable experience. Follows Apple's inline suggestion pattern — lightweight,
//  non-intrusive, dismissible.
//

import SwiftUI

struct SkillSuggestionBanner: View {
    @Environment(AppState.self) private var appState
    @State private var autoDismissTask: Task<Void, Never>?

    private var queue: SkillSuggestionQueue {
        appState.agent.skillSuggestionQueue
    }

    var body: some View {
        if queue.showBanner {
            VStack(spacing: 6) {
                ForEach(queue.pendingSuggestions) { suggestion in
                    suggestionRow(suggestion)
                }
            }
            .padding(.horizontal, SageDesign.Spacing.lg)
            .padding(.vertical, SageDesign.Spacing.sm)
            .transition(
                .asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .bottom)),
                    removal: .opacity
                )
            )
            .onAppear { scheduleAutoDismiss() }
            .onChange(of: queue.pendingSuggestions.count) { _, _ in
                scheduleAutoDismiss()
            }
            .onDisappear { autoDismissTask?.cancel() }
        }
    }

    @ViewBuilder
    private func suggestionRow(_ suggestion: SkillSuggestion) -> some View {
        HStack(spacing: SageDesign.Spacing.sm) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 12))
                .foregroundStyle(.yellow)

            VStack(alignment: .leading, spacing: 2) {
                Text(bannerTitle(for: suggestion))
                    .font(.system(size: SageDesign.Typography.bodySize, weight: .medium))
                    .lineLimit(1)

                Text(suggestion.skillDescription)
                    .font(.system(size: SageDesign.Typography.microSize))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Button("Save") {
                confirmSuggestion(suggestion)
            }
            .font(.system(size: SageDesign.Typography.microSize, weight: .semibold))
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            Button {
                withAnimation(SageDesign.Motion.expandAnimation) {
                    queue.dismiss(suggestion.id)
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss suggestion")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.yellow.opacity(0.2), lineWidth: 0.5)
        }
    }

    private func bannerTitle(for suggestion: SkillSuggestion) -> String {
        switch suggestion.type {
        case .new:
            return "New experience: \(suggestion.skillName)"
        case .enhance:
            return "Enhance skill: \(suggestion.skillName)"
        }
    }

    private func confirmSuggestion(_ suggestion: SkillSuggestion) {
        guard let confirmed = queue.confirm(suggestion.id) else { return }

        Task {
            do {
                switch confirmed.type {
                case .new:
                    try SkillWriter.createSkill(
                        name: confirmed.skillName,
                        description: confirmed.skillDescription,
                        body: confirmed.body
                    )
                case .enhance:
                    guard let existing = appState.capabilities.skills
                        .first(where: { $0.name == confirmed.skillName }) else {
                        return // Target skill no longer exists — discard silently
                    }
                    try SkillWriter.enhanceSkill(
                        existingRecord: existing,
                        description: confirmed.skillDescription,
                        body: confirmed.body
                    )
                }
                await appState.capabilities.reloadSkills(
                    projectRoot: appState.agent.focusedProject?.rootURL
                )
            } catch {
                // Silently fail — the suggestion is already dismissed from UI
            }
        }
    }

    private func scheduleAutoDismiss() {
        autoDismissTask?.cancel()
        autoDismissTask = Task {
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled else { return }
            withAnimation(SageDesign.Motion.expandAnimation) {
                queue.dismissAll()
            }
        }
    }
}
