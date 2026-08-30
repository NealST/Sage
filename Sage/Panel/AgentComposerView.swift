//
//  AgentComposerView.swift
//  Sage
//
//  Composer + slash autocomplete — isolated from transcript / chrome observation.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AgentComposerView: View {
    @Environment(AppState.self) private var appState
    @Environment(AgentSession.self) var session
    @Environment(\.pathGuardPolicy) var pathGuardPolicy
    @Environment(\.sageTypography) private var type

    @FocusState.Binding var isInputFocused: Bool
    @Binding var stickToBottom: Bool

    @State var slashSuggestions: [ComposerSlashSuggestion] = []
    @State var selectedSuggestionIndex: Int = 0
    @State var isDropTargeted = false
    @State var attachmentImportCount = 0
    @State var isPreparingAttachments = false
    @State var attachmentHintGeneration: UInt = 0

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
                    showPersistentAttachmentHint(
                        "Wait for Sage to finish before adding attachments."
                    )
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
        .confirmationDialog(
            "Sage is still working",
            isPresented: turnInterruptPresented,
            titleVisibility: .visible
        ) {
            Button("Add to Queue") {
                session.agent.queueTurnInterrupt()
            }
            Button("Redirect Now") {
                Task { await session.agent.steerTurnInterrupt() }
            }
            Button("Cancel", role: .cancel) {
                restoreTurnInterruptDraft()
            }
        } message: {
            Text(
                "Add this message to the queue, or redirect the current turn now."
            )
        }
        .onChange(of: session.attachmentHint) { _, hint in
            guard let hint else { return }
            NSAccessibility.post(
                element: NSApp as Any,
                notification: .announcementRequested,
                userInfo: [
                    .announcement: hint,
                    .priority: NSAccessibilityPriorityLevel.medium.rawValue,
                ]
            )
        }
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

    var blocksTyping: Bool {
        session.agent.blocksNewInput || isPreparingAttachments
    }
    var blocksSubmit: Bool { blocksTyping || attachmentImportCount > 0 }
    private var canSubmit: Bool {
        !blocksSubmit && (
            !session.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !session.draftAttachments.isEmpty
        )
    }

    private func handleDeleteKey() -> KeyPress.Result {
        if session.draft.isEmpty, let last = session.draftAttachments.last {
            removeAttachment(last)
            return .handled
        }
        return .ignored
    }
}
