//
//  AgentComposerView.swift
//  Sage
//
//  Composer + slash autocomplete — isolated from transcript / chrome observation.
//

import SwiftUI

struct AgentComposerView: View {
    @Environment(AppState.self) private var appState
    @Environment(AgentSession.self) private var session
    @Environment(\.sageTypography) private var type

    @FocusState.Binding var isInputFocused: Bool
    @Binding var stickToBottom: Bool

    @State private var skillSuggestions: [SlashCommandDefinition] = []
    @State private var selectedSuggestionIndex: Int = 0

    var body: some View {
        @Bindable var session = session

        VStack(alignment: .leading, spacing: 6) {
            if !skillSuggestions.isEmpty {
                suggestionList
            }

            HStack(alignment: .center, spacing: SageDesign.Spacing.sm) {
                TextField(composerPlaceholder, text: $session.draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: type.input))
                    .lineLimit(1...5)
                    .focused($isInputFocused)
                    .disabled(blocksTyping)
                    .onSubmit(handleComposerSubmit)
                    .onChange(of: session.draft) { _, newValue in
                        updateSkillSuggestions(newValue)
                    }
                    .onKeyPress(.upArrow) { moveSuggestionSelection(by: -1) }
                    .onKeyPress(.downArrow) { moveSuggestionSelection(by: 1) }
                    .onKeyPress(.escape) { dismissSuggestionsIfNeeded() }
                    .accessibilityHint(composerAccessibilityHint)

                if !session.draft.isEmpty && !blocksSubmit {
                    Text(skillSuggestions.isEmpty ? "Submit ⏎" : "Select ⏎")
                        .font(.system(size: type.micro, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .sagePanelBackground(cornerRadius: 12)

            HStack(spacing: SageDesign.Spacing.sm) {
                Text(appState.settings.model)
                    .font(.system(size: type.micro))
                    .foregroundStyle(.tertiary)

                if !session.skills.saveJobs.isEmpty {
                    SkillSaveStatusIndicator()
                        .transition(.opacity)
                }

                Spacer(minLength: 0)
                if case .awaitingConfirmation = session.agent.state.phase {
                    Label("Run or Cancel the pending plan", systemImage: SageDesign.Symbol.pending)
                        .font(.system(size: type.micro))
                        .foregroundStyle(.orange.opacity(0.95))
                        .labelStyle(.titleAndIcon)
                } else if session.agent.canStop || blocksTyping {
                    Text(
                        session.agent.state.hasPendingPlan && !session.agent.canStop
                            ? "Resolve the pending plan first…"
                            : "Sage is working…"
                    )
                    .font(.system(size: type.micro))
                    .foregroundStyle(.secondary)
                }
            }
            .animation(SageDesign.Motion.expandAnimation, value: session.skills.saveJobs.count)
        }
        .padding(.horizontal, SageDesign.Spacing.lg)
        .padding(.vertical, SageDesign.Spacing.md)
    }

    private var suggestionList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(skillSuggestions.enumerated()), id: \.element.id) { index, command in
                Button {
                    session.draft = "/\(command.name)"
                    skillSuggestions = []
                    submit()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: command.kind == .builtin ? "bookmark" : "sparkles")
                            .font(.system(size: type.icon))
                            .foregroundStyle(.secondary)
                        Text("/\(command.name)")
                            .font(.system(size: type.body, weight: .medium))
                        if !command.description.isEmpty {
                            Text("— \(command.description)")
                                .font(.system(size: type.micro))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        index == selectedSuggestionIndex
                            ? Color.accentColor.opacity(0.12)
                            : Color.clear
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private var composerPlaceholder: String {
        if session.agent.state.hasPendingPlan {
            return "Finish the pending plan first…"
        }
        if blocksTyping {
            return "Sage is working…"
        }
        return "Ask Sage…"
    }

    private var composerAccessibilityHint: String {
        if session.agent.state.hasPendingPlan {
            return "Run, cancel, or retry the pending plan before sending"
        }
        if blocksTyping { return "Unavailable while Sage is working" }
        if !skillSuggestions.isEmpty {
            return "Use Up and Down arrows to choose a command, Return to select, Escape to dismiss"
        }
        return "Press Return to send"
    }

    private var blocksTyping: Bool { session.agent.blocksNewInput }
    private var blocksSubmit: Bool { blocksTyping }

    private func handleComposerSubmit() {
        if applySelectedSuggestion() { return }
        guard !blocksSubmit else { return }
        submit()
    }

    @discardableResult
    private func applySelectedSuggestion() -> Bool {
        guard !skillSuggestions.isEmpty,
              skillSuggestions.indices.contains(selectedSuggestionIndex)
        else { return false }
        let command = skillSuggestions[selectedSuggestionIndex]
        session.draft = "/\(command.name)"
        skillSuggestions = []
        submit()
        return true
    }

    private func moveSuggestionSelection(by delta: Int) -> KeyPress.Result {
        guard !skillSuggestions.isEmpty else { return .ignored }
        let count = skillSuggestions.count
        selectedSuggestionIndex = (selectedSuggestionIndex + delta + count) % count
        return .handled
    }

    private func dismissSuggestionsIfNeeded() -> KeyPress.Result {
        guard !skillSuggestions.isEmpty else { return .ignored }
        withAnimation(.easeOut(duration: 0.15)) { skillSuggestions = [] }
        return .handled
    }

    private func submit() {
        let trimmed = session.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !blocksSubmit else { return }
        stickToBottom = true
        skillSuggestions = []
        Task {
            let accepted = await session.agent.submit(trimmed)
            if accepted {
                session.draft = ""
            }
        }
    }

    private func updateSkillSuggestions(_ draft: String) {
        guard draft.hasPrefix("/"), !draft.contains(" ") else {
            if !skillSuggestions.isEmpty {
                withAnimation(.easeOut(duration: 0.15)) { skillSuggestions = [] }
            }
            return
        }
        let prefix = String(draft.dropFirst()).lowercased()
        let available = session.agent.availableSlashCommandDefinitions
        let filtered = prefix.isEmpty
            ? available
            : available.filter { $0.name.lowercased().hasPrefix(prefix) }
        let capped = Array(filtered.prefix(6))
        withAnimation(.easeOut(duration: 0.15)) {
            let resetIndex = skillSuggestions.isEmpty
            skillSuggestions = capped
            if resetIndex || !capped.indices.contains(selectedSuggestionIndex) {
                selectedSuggestionIndex = 0
            }
        }
    }
}
