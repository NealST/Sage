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
    /// ⌘↑/⌘↓ recall: index into `session.inputHistory`, nil = live draft.
    @State var historyRecallIndex: Int?
    @State var liveDraftBeforeRecall: String?
    /// Removed attachment awaiting its undo window to close (U9: flick-remove
    /// is a slip-prone gesture — managed copies are reclaimed only after it).
    @State var removedAttachment: MessageAttachment?
    @State var removedAttachmentIndex: Int?
    @State var attachmentRemovalTask: Task<Void, Never>?

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

                if removedAttachment != nil {
                    removedAttachmentRow
                        .transition(.opacity)
                }

                HStack(alignment: .center, spacing: SageDesign.Spacing.small) {
                    attachButton
                    inputField

                    // Primary action: send morphs to stop while the turn is in
                    // flight. The composer never scrolls away, so this stays
                    // reachable during long streaming replies.
                    if !slashSuggestions.isEmpty {
                        Text("Select ⏎")
                            .sageMicro(type.micro, weight: .medium)
                            .foregroundStyle(.secondary)
                    }

                    composerSubmitButton
                }
            }
            .padding(.horizontal, SageDesign.Spacing.medium)
            .padding(.vertical, 10)
            .sagePanelBackground(cornerRadius: SageDesign.Glass.panel)
            .overlay {
                // Focus reads as a hairline tint on glass — the pre-glass
                // 1.5pt accent ring outweighed the material it sits on.
                RoundedRectangle(cornerRadius: SageDesign.Glass.panel, style: .continuous)
                    .strokeBorder(
                        Color.accentColor.opacity(composerStrokeOpacity),
                        lineWidth: 1
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
                HStack(alignment: .top, spacing: SageDesign.Spacing.small) {
                    Text(hint)
                        .sageFont(type.caption)
                        .foregroundStyle(SageDesign.Palette.warning)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        dismissAttachmentHint()
                    } label: {
                        Image(systemName: "xmark")
                            .sageMicro(type.micro, weight: .semibold)
                            .padding(4)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Dismiss attachment notice")
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Attachment notice: \(hint)")
                .transition(.opacity)
            }

            statusRow
        }
        .padding(.horizontal, SageDesign.Spacing.large)
        .padding(.vertical, SageDesign.Spacing.medium)
        .animation(SageDesign.Motion.expandAnimation, value: session.draftAttachments.count)
        .animation(SageDesign.Motion.expandAnimation, value: removedAttachment)
        .animation(SageDesign.Motion.expandAnimation, value: session.attachmentHint)
        .animation(SageDesign.Motion.expandAnimation, value: isInputFocused)
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

    /// Model chip · save jobs · queued count · working/attention status.
    private var statusRow: some View {
        HStack(spacing: SageDesign.Spacing.small) {
            Text(appState.settings.resolvedModel(for: .execute))
                .sageMicro(type.micro, weight: .medium)
                .foregroundStyle(.secondary)

            if !session.skills.saveJobs.isEmpty {
                SkillSaveStatusIndicator()
                    .transition(.opacity)
            }

            let queuedCount = session.agent.state.turnInput.items.count
            if queuedCount > 0 {
                Label(
                    queuedCount == 1 ? "1 queued" : "\(queuedCount) queued",
                    systemImage: "tray.full"
                )
                .sageMicro(type.micro)
                .foregroundStyle(.secondary)
                .transition(.opacity)
            }

            Spacer(minLength: 0)
            if attachmentImportCount > 0 {
                Label("Adding attachments…", systemImage: "arrow.down.circle")
                    .sageMicro(type.micro)
                    .foregroundStyle(.secondary)
            } else if case .awaitingConfirmation = session.agent.state.phase {
                // Safety-critical pending decision — the only status that
                // outranks the chrome, so it gets caption weight + full
                // warning saturation instead of micro.
                Label(pendingConfirmationHint, systemImage: SageDesign.Symbol.pending)
                    .sageFont(type.caption, weight: .semibold)
                    .foregroundStyle(SageDesign.Palette.warning)
                    .labelStyle(.titleAndIcon)
            } else if session.agent.canStop || blocksTyping {
                Text(
                    session.agent.state.hasPendingPlan && !session.agent.canStop
                        ? "Resolve the pending plan first…"
                        : "Sage is working…"
                )
                .sageMicro(type.micro)
                .foregroundStyle(.secondary)
            }
        }
        .animation(SageDesign.Motion.expandAnimation, value: session.skills.saveJobs.count)
        .animation(
            SageDesign.Motion.expandAnimation,
            value: session.agent.state.turnInput.items.count
        )
    }

    @ViewBuilder private var inputField: some View {
        @Bindable var session = session
        TextField(composerPlaceholder, text: $session.draft, axis: .vertical)
            .textFieldStyle(.plain)
            .sageFont(type.input)
            .lineLimit(1...5)
            .focused($isInputFocused)
            .disabled(blocksTyping)
            .onSubmit(handleComposerSubmit)
            .onChange(of: session.draft) { _, newValue in
                updateSkillSuggestions(newValue)
            }
            .onKeyPress(keys: [.upArrow]) { press in
                if press.modifiers.contains(.command) {
                    return recallInputHistory(1)
                }
                return moveSuggestionSelection(by: -1)
            }
            .onKeyPress(keys: [.downArrow]) { press in
                if press.modifiers.contains(.command) {
                    return recallInputHistory(-1)
                }
                return moveSuggestionSelection(by: 1)
            }
            .onKeyPress(.escape) { dismissSuggestionsIfNeeded() }
            .onKeyPress(.delete) { handleDeleteKey() }
            .accessibilityHint(composerAccessibilityHint)
    }

    private var attachButton: some View {
        Button("Add files", systemImage: "plus") {
            pickAttachments()
        }
        .labelStyle(.iconOnly)
        .sageFont(type.caption, weight: .semibold)
        .foregroundStyle(.secondary)
        .frame(width: 22, height: 22)
        .buttonStyle(SagePressableChipButtonStyle())
        // Hit slop beyond the visual chip — small targets should not stay small.
        .padding(3)
        .contentShape(Rectangle())
        .disabled(blocksTyping || isPreparingAttachments)
        .opacity(blocksTyping || isPreparingAttachments ? 0.45 : 1)
        .keyboardShortcut("a", modifiers: [.command, .shift])
        .help("Add files to this message")
    }

    /// Send ↔ Stop: one prominent control whose symbol replaces itself when
    /// the turn starts and ends, so the escape hatch lives in the same place
    /// the user just clicked to send.
    @ViewBuilder private var composerSubmitButton: some View {
        Button {
            if session.agent.canStop {
                session.agent.stop()
            } else {
                handleComposerSubmit()
            }
        } label: {
            Image(systemName: session.agent.canStop ? "stop.fill" : "arrow.up")
                .sageFont(type.body, weight: .semibold)
                .frame(width: 24, height: 24)
                .sageSubmitSymbolReplaceTransition()
        }
        .buttonStyle(.glassProminent)
        .controlSize(.small)
        // Hit slop beyond the visual chip — small targets should not stay small.
        .padding(2)
        .contentShape(Rectangle())
        .disabled(!session.agent.canStop && !canSubmit)
        .sageShortcut(.cancelAction, enabled: session.agent.canStop)
        .animation(SageDesign.Motion.expandAnimation, value: session.agent.canStop)
        .help(
            session.agent.canStop
                ? "Stop this turn (Esc)"
                : "Send this message (Return)"
        )
        .accessibilityLabel(
            session.agent.canStop ? "Stop this turn" : "Send this message"
        )
    }

    private var composerStrokeOpacity: Double {
        if isDropTargeted { return 0.7 }
        return isInputFocused ? 0.35 : 0
    }

    /// Forgiveness for a slip (Apple: "easy undo for slips"): the flick-to-
    /// remove gesture commits fast, so the managed file copy survives a few
    /// seconds behind this row.
    private var removedAttachmentRow: some View {
        HStack(spacing: SageDesign.Spacing.small) {
            Text(
                removedAttachment.map { "Removed “\($0.displayName)”" } ?? ""
            )
            .sageMicro(type.micro)
            .foregroundStyle(.secondary)
            .lineLimit(1)

            Button("Undo") {
                undoAttachmentRemoval()
            }
            .sageMicro(type.micro, weight: .semibold)
            .foregroundStyle(Color.accentColor)
            .buttonStyle(.plain)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
            .accessibilityHint("Puts the removed attachment back")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            removedAttachment.map { "Removed \($0.displayName)" } ?? "Attachment removed"
        )
    }

    private var suggestionList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(slashSuggestions.enumerated()), id: \.element.id) { index, suggestion in
                let isSelected = index == selectedSuggestionIndex
                Button {
                    applySuggestion(suggestion)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: suggestion.systemImage)
                            .sageFont(type.icon)
                            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                        Text(suggestion.title)
                            .sageFont(type.body, weight: .medium)
                        if !suggestion.description.isEmpty {
                            Text("— \(suggestion.description)")
                                .sageMicro(type.micro)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        isSelected ? Color.accentColor.opacity(0.12) : Color.clear
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // Hover tracks selection so the highlighted row and the row
                // Return inserts are always the same one.
                .onHover { hovering in
                    if hovering {
                        selectedSuggestionIndex = index
                    }
                }
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .sagePanelBackground(cornerRadius: SageDesign.Glass.chip, weight: .clear)
        .sageGlassMaterialize()
        .transition(SageDesign.Glass.appearTransition)
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
