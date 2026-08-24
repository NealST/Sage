//
//  AgentComposerView.swift
//  Sage
//
//  Composer + slash autocomplete — isolated from transcript / chrome observation.
//

import SwiftUI
import UniformTypeIdentifiers

struct AgentComposerView: View {
    @Environment(AppState.self) private var appState
    @Environment(AgentSession.self) private var session
    @Environment(\.pathGuardPolicy) private var pathGuardPolicy
    @Environment(\.sageTypography) private var type

    @FocusState.Binding var isInputFocused: Bool
    @Binding var stickToBottom: Bool

    @State private var slashSuggestions: [ComposerSlashSuggestion] = []
    @State private var selectedSuggestionIndex: Int = 0
    @State private var isDropTargeted = false
    @State private var attachmentImportCount = 0
    @State private var isPreparingAttachments = false
    @State private var attachmentHintGeneration: UInt = 0

    var body: some View {
        @Bindable var session = session

        VStack(alignment: .leading, spacing: 6) {
            if !slashSuggestions.isEmpty {
                suggestionList
            }

            VStack(alignment: .leading, spacing: 8) {
                if !session.draftAttachments.isEmpty {
                    AttachmentChipBar(
                        attachments: session.draftAttachments,
                        selectedID: nil,
                        showsRemove: true,
                        onSelect: selectAttachment,
                        onRemove: removeAttachment
                    )
                    .transition(.opacity)
                }

                HStack(alignment: .center, spacing: SageDesign.Spacing.small) {
                    attachButton

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
                        .onKeyPress(.delete) { handleDeleteKey() }
                        .accessibilityHint(composerAccessibilityHint)

                    if canSubmit && slashSuggestions.isEmpty {
                        Text("Submit ⏎")
                            .font(.system(size: type.micro, weight: .medium))
                            .foregroundStyle(.tertiary)
                    } else if !slashSuggestions.isEmpty {
                        Text("Select ⏎")
                            .font(.system(size: type.micro, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .sagePanelBackground(cornerRadius: 12)
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        Color.accentColor.opacity(isDropTargeted ? 0.85 : 0),
                        lineWidth: 1.5
                    )
            }
            .onDrop(of: [.fileURL, .image], isTargeted: $isDropTargeted) { providers in
                guard !blocksTyping else {
                    session.attachmentHint = "Wait for Sage to finish before adding attachments."
                    return false
                }
                Task { await applyDrop(providers) }
                return true
            }
            .background {
                ComposerPasteMonitor(isEnabled: isInputFocused, onPaste: handlePasteboard)
            }

            if let hint = session.attachmentHint {
                Text(hint)
                    .font(.system(size: type.micro))
                    .foregroundStyle(.orange.opacity(0.95))
                    .accessibilityLabel("Attachment notice: \(hint)")
                    .transition(.opacity)
            }

            HStack(spacing: SageDesign.Spacing.small) {
                Text(appState.settings.resolvedModel(for: .execute))
                    .font(.system(size: type.micro))
                    .foregroundStyle(.tertiary)

                if !session.skills.saveJobs.isEmpty {
                    SkillSaveStatusIndicator()
                        .transition(.opacity)
                }

                Spacer(minLength: 0)
                if attachmentImportCount > 0 {
                    Label("Adding attachments…", systemImage: "arrow.down.circle")
                        .font(.system(size: type.micro))
                        .foregroundStyle(.secondary)
                } else if case .awaitingConfirmation = session.agent.state.phase {
                    Label(pendingConfirmationHint, systemImage: SageDesign.Symbol.pending)
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
        .padding(.horizontal, SageDesign.Spacing.large)
        .padding(.vertical, SageDesign.Spacing.medium)
        .animation(SageDesign.Motion.expandAnimation, value: session.draftAttachments.count)
        .animation(SageDesign.Motion.expandAnimation, value: session.attachmentHint)
    }

    private var attachButton: some View {
        Button {
            pickAttachments()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(blocksTyping || isPreparingAttachments)
        .opacity(blocksTyping || isPreparingAttachments ? 0.45 : 1)
        .keyboardShortcut("a", modifiers: [.command, .shift])
        .help("Add files to this message")
        .accessibilityLabel("Add files")
    }

    private var suggestionList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(slashSuggestions.enumerated()), id: \.element.id) { index, suggestion in
                Button {
                    applySuggestion(suggestion)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: suggestion.systemImage)
                            .font(.system(size: type.icon))
                            .foregroundStyle(.secondary)
                        Text(suggestion.title)
                            .font(.system(size: type.body, weight: .medium))
                        if !suggestion.description.isEmpty {
                            Text("— \(suggestion.description)")
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

    private var pendingConfirmationHint: String {
        switch session.agent.turnChrome {
        case .toolRoundLimit:
            return "Continue for more tool rounds, or finish"

        case .toolApproval:
            return "Allow, skip, or stop this tool"

        default:
            return "Run or Cancel the pending plan"
        }
    }

    private var composerPlaceholder: String {
        if session.agent.state.hasPendingPlan {
            return "Finish the pending plan first…"
        }
        if blocksTyping {
            return "Sage is working…"
        }
        if isDropTargeted {
            return "Add to this message"
        }
        if !session.draftAttachments.isEmpty {
            return "Ask about these files…"
        }
        return "Ask Sage…"
    }

    private var composerAccessibilityHint: String {
        if session.agent.state.hasPendingPlan {
            return "Run, cancel, or retry the pending plan before sending"
        }
        if blocksTyping { return "Unavailable while Sage is working" }
        if !slashSuggestions.isEmpty {
            return "Use Up and Down arrows to choose a command, Return to select, Escape to dismiss"
        }
        return "Press Return to send. Shift-Command-A adds files."
    }

    private var blocksTyping: Bool {
        session.agent.blocksNewInput || isPreparingAttachments
    }
    private var blocksSubmit: Bool { blocksTyping || attachmentImportCount > 0 }
    private var canSubmit: Bool {
        !blocksSubmit && (
            !session.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !session.draftAttachments.isEmpty
        )
    }

    private func handleComposerSubmit() {
        if applySelectedSuggestion() { return }
        guard !blocksSubmit else { return }
        submit()
    }

    @discardableResult
    private func applySelectedSuggestion() -> Bool {
        guard !slashSuggestions.isEmpty,
              slashSuggestions.indices.contains(selectedSuggestionIndex)
        else { return false }
        applySuggestion(slashSuggestions[selectedSuggestionIndex])
        return true
    }

    private func applySuggestion(_ suggestion: ComposerSlashSuggestion) {
        session.draft = suggestion.insertDraft
        slashSuggestions = []
        if suggestion.submitOnSelect {
            submit()
        }
    }

    private func moveSuggestionSelection(by delta: Int) -> KeyPress.Result {
        guard !slashSuggestions.isEmpty else { return .ignored }
        let count = slashSuggestions.count
        selectedSuggestionIndex = (selectedSuggestionIndex + delta + count) % count
        return .handled
    }

    private func dismissSuggestionsIfNeeded() -> KeyPress.Result {
        guard !slashSuggestions.isEmpty else { return .ignored }
        withAnimation(.easeOut(duration: 0.15)) { slashSuggestions = [] }
        return .handled
    }

    private func submit() {
        let trimmed = session.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachments = session.draftAttachments
        guard !trimmed.isEmpty || !attachments.isEmpty else { return }
        guard !blocksSubmit else { return }
        if !attachments.isEmpty, trimmed.hasPrefix("/") {
            session.attachmentHint = "Remove attachments before running a slash command."
            return
        }
        let unavailable = attachments.filter { !$0.isAvailable }
        if !unavailable.isEmpty {
            let names = unavailable.map(\.displayName).joined(separator: ", ")
            session.attachmentHint = "Remove missing or unreadable attachments: \(names)."
            return
        }
        stickToBottom = true
        slashSuggestions = []
        Task {
            isPreparingAttachments = true
            let failedImages = await Task.detached(priority: .userInitiated) {
                attachments.filter {
                    $0.kind == .image && !AttachmentImageEncoder.canEncode($0.fileURL)
                }
            }.value
            guard failedImages.isEmpty else {
                isPreparingAttachments = false
                session.attachmentHint = "Couldn’t prepare for vision: "
                    + failedImages.map(\.displayName).joined(separator: ", ")
                    + "."
                return
            }
            let accepted = await session.agent.submit(trimmed, attachments: attachments)
            isPreparingAttachments = false
            if accepted {
                session.resetComposer(discardManagedCopies: false)
            }
        }
    }

    private func pickAttachments() {
        guard !blocksTyping else { return }
        guard let outcome = AttachmentImport.pickFromOpenPanel(
            policy: pathGuardPolicy,
            into: session.draftAttachments
        ) else { return }
        applyImport(outcome)
    }

    private func handlePasteboard() -> Bool {
        guard !blocksTyping else { return false }
        guard let outcome = AttachmentImport.fromPasteboard(into: session.draftAttachments) else {
            return false
        }
        applyImport(outcome)
        return true
    }

    private func applyDrop(_ providers: [NSItemProvider]) async {
        guard !blocksTyping else { return }
        let revision = session.composerRevision
        attachmentImportCount += 1
        defer { attachmentImportCount -= 1 }
        let outcome = await AttachmentImport.fromItemProviders(
            providers,
            into: []
        )
        guard session.composerRevision == revision else {
            MessageAttachment.deleteManagedCopies(outcome.attachments)
            return
        }
        let merged = AttachmentImport.merge(
            outcome.attachments.map { .success($0) },
            into: session.draftAttachments
        )
        applyImport(
            AttachmentImportOutcome(
                attachments: merged.attachments,
                hint: merged.hint ?? outcome.hint
            )
        )
    }

    private func applyImport(_ outcome: AttachmentImportOutcome) {
        session.draftAttachments = outcome.attachments
        session.attachmentHint = outcome.hint
        if outcome.hint != nil {
            attachmentHintGeneration &+= 1
            let generation = attachmentHintGeneration
            Task {
                try? await Task.sleep(for: .seconds(4))
                if attachmentHintGeneration == generation {
                    session.attachmentHint = nil
                }
            }
        }
    }

    private func selectAttachment(_ attachment: MessageAttachment) {
        guard let index = session.draftAttachments.firstIndex(where: { $0.id == attachment.id })
        else { return }
        QuickLookPresenter.shared.preview(
            urls: session.draftAttachments.map(\.fileURL),
            selectedIndex: index
        )
    }

    private func removeAttachment(_ attachment: MessageAttachment) {
        session.draftAttachments.removeAll { $0.id == attachment.id }
        MessageAttachment.deleteManagedCopies([attachment])
        if session.draftAttachments.count < MessageAttachment.maxCount,
           session.attachmentHint == AttachmentImport.tooManyHint {
            session.attachmentHint = nil
        }
    }

    private func handleDeleteKey() -> KeyPress.Result {
        if session.draft.isEmpty, let last = session.draftAttachments.last {
            removeAttachment(last)
            return .handled
        }
        return .ignored
    }

    private func updateSkillSuggestions(_ draft: String) {
        let lowered = draft.lowercased()
        let next: [ComposerSlashSuggestion]
        if lowered.hasPrefix("/schedule"), !lowered.hasPrefix("/schedule-") {
            next = ScheduleCadenceParser.autocompleteInserts(forDraft: draft).map { insert in
                ComposerSlashSuggestion(
                    id: insert.id,
                    title: "/schedule \(insert.insert)",
                    description: insert.description,
                    insertDraft: "/schedule \(insert.insert) ",
                    submitOnSelect: false,
                    systemImage: "clock"
                )
            }
        } else if draft.hasPrefix("/"), !draft.contains(" ") {
            let prefix = String(draft.dropFirst()).lowercased()
            let available = session.agent.availableSlashCommandDefinitions
            let filtered = prefix.isEmpty
                ? available
                : available.filter { $0.name.lowercased().hasPrefix(prefix) }
            next = Array(filtered.prefix(6)).map { command in
                let isSchedule = command.name == "schedule"
                return ComposerSlashSuggestion(
                    id: command.name,
                    title: "/\(command.name)",
                    description: command.description,
                    insertDraft: isSchedule ? "/schedule " : "/\(command.name)",
                    submitOnSelect: !isSchedule,
                    systemImage: command.kind == .builtin ? "bookmark" : "sparkles"
                )
            }
        } else {
            next = []
        }
        withAnimation(.easeOut(duration: 0.15)) {
            let resetIndex = slashSuggestions.isEmpty
            slashSuggestions = next
            if resetIndex || !next.indices.contains(selectedSuggestionIndex) {
                selectedSuggestionIndex = 0
            }
        }
    }
}

private struct ComposerSlashSuggestion: Identifiable, Equatable {
    let id: String
    let title: String
    let description: String
    let insertDraft: String
    let submitOnSelect: Bool
    let systemImage: String
}
