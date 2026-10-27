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

        VStack(alignment: .leading, spacing: SageDesign.Spacing.small) {
            if !slashSuggestions.isEmpty {
                suggestionList
            }

            VStack(alignment: .leading, spacing: SageDesign.Spacing.small) {
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

                if case .awaitingConfirmation = session.agent.state.phase {
                    awaitingConfirmationRow
                        .transition(.opacity)
                }

                HStack(alignment: .center, spacing: SageDesign.Spacing.small) {
                    attachButton
                    inputField
                        // Slash-menu hint rides the field's trailing edge so
                        // the send/stop anchor never shifts position when the
                        // menu opens — the primary action is the composer's
                        // one fixed point.
                        .overlay(alignment: .trailing) {
                            if !slashSuggestions.isEmpty {
                                HStack(spacing: 2) {
                                    Text("Select")
                                    Image(systemName: SageDesign.Symbol.returnKey)
                                }
                                .sageMicro(type.micro, weight: .medium)
                                .foregroundStyle(.secondary)
                                .padding(.trailing, 2)
                                .allowsHitTesting(false)
                            }
                        }

                    // Primary action: send morphs to stop while the turn is in
                    // flight. The composer never scrolls away, so this stays
                    // reachable during long streaming replies.
                    composerSubmitButton
                }
            }
            .padding(.horizontal, SageDesign.Spacing.medium)
            .padding(.vertical, SageDesign.Spacing.medium)
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
                        .foregroundStyle(SageDesign.Palette.warningText)
                        .fixedSize(horizontal: false, vertical: true)
                    SageDismissButton(
                        action: dismissAttachmentHint,
                        label: "Dismiss attachment notice"
                    )
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
        .animation(SageDesign.Motion.expandAnimation, value: session.agent.state.phase)
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
            ComposerModelPicker()

            if let localEngineNote {
                Label(localEngineNote, systemImage: "hourglass")
                    .sageMicro(type.micro)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }

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
        .animation(SageDesign.Motion.expandAnimation, value: localEngineNote)
    }

    /// Loading a multi-GB local model takes tens of seconds — surface the
    /// engine's warm-up inside the row so the wait reads as progress, not a
    /// hang (the first request triggers the same load).
    private var localEngineNote: String? {
        switch LocalEngineObserver.shared.status {
        case .loading:
            return "Loading local model…"
        case .downloading(_, let progress):
            return "Fetching weights \(Int(progress * 100))%…"
        case .idle, .ready, .failed:
            return nil
        }
    }

    /// Safety-critical pending decision — lives inside the composer surface so
    /// it reads as part of the blocked input, not a footnote at the window's
    /// bottom edge. Caption weight + full warning saturation, above micro.
    private var awaitingConfirmationRow: some View {
        Label(pendingConfirmationHint, systemImage: SageDesign.Symbol.pending)
            .sageFont(type.caption, weight: .semibold)
            .foregroundStyle(SageDesign.Palette.warningText)
            .labelStyle(.titleAndIcon)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var inputField: some View {
        @Bindable var session = session
        TextField(composerPlaceholder, text: $session.draft, axis: .vertical)
            .textFieldStyle(.plain)
            .sageFont(type.input)
            .lineLimit(1...12)
            .scrollIndicators(.never)
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
            .sageComposerSpellChecking(isFocused: isInputFocused)
            .accessibilityHint(composerAccessibilityHint)
            .help("Return sends · Option-Return adds a new line")
    }

    private var attachButton: some View {
        Button("Add files", systemImage: "paperclip") {
            pickAttachments()
        }
        .labelStyle(.iconOnly)
        .symbolRenderingMode(.hierarchical)
        .sageFont(type.caption, weight: .semibold)
        .foregroundStyle(.secondary)
        .frame(
            width: SageDesign.Control.iconButton,
            height: SageDesign.Control.iconButton
        )
        .sageGlassButton()
        .sageHitSlop(visualSize: SageDesign.Control.iconButton)
        .disabled(blocksTyping || isPreparingAttachments)
        // ⌘U, not ⇧⌘A (Deselect All): Underline is meaningless here — no rich
        // text anywhere in Sage — and ⌘U-for-attach matches the Slack idiom.
        .keyboardShortcut("u", modifiers: [.command])
        .help("Add files to this message")
    }

    /// Send ↔ Stop: same quiet glass chip as the paperclip, so it sits in
    /// the composer instead of a second prominent material. Accent lives on
    /// the arrow, not a filled blue pill.
    @ViewBuilder private var composerSubmitButton: some View {
        let isStop = session.agent.canStop
        let isArmed = isStop || canSubmit
        Button {
            if isStop {
                session.agent.stop()
            } else {
                handleComposerSubmit()
            }
        } label: {
            Image(systemName: isStop ? "stop.fill" : "arrow.up")
                .sageFont(type.caption, weight: .semibold)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(submitForeground(isStop: isStop, isArmed: isArmed))
                .frame(
                    width: SageDesign.Control.iconButton,
                    height: SageDesign.Control.iconButton
                )
                .sageSubmitSymbolReplaceTransition()
        }
        .sageGlassButton()
        .sageHitSlop(visualSize: SageDesign.Control.iconButton)
        // Stays visible when unarmed — the composer's fixed action anchor
        // reads as a disabled control (system glass dimming), not a hole.
        .disabled(!isArmed)
        .sageShortcut(.cancelAction, enabled: isStop)
        .animation(SageDesign.Motion.expandAnimation, value: isArmed)
        .animation(SageDesign.Motion.expandAnimation, value: isStop)
        .help(
            isStop
                ? "Stop this turn (Esc)"
                : "Send this message (Return)"
        )
        .accessibilityLabel(
            isStop ? "Stop this turn" : "Send this message"
        )
    }

    private func submitForeground(isStop: Bool, isArmed: Bool) -> AnyShapeStyle {
        if isStop { return AnyShapeStyle(.primary) }
        if isArmed { return AnyShapeStyle(Color.accentColor) }
        return AnyShapeStyle(.secondary)
    }

    private var composerStrokeOpacity: Double {
        if isDropTargeted { return min(SageDesign.Chrome.accentRingOpacity + 0.1, 1) }
        return isInputFocused ? SageDesign.Chrome.accentRingOpacity : 0
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
            .buttonStyle(SagePlainActionButtonStyle())
            .foregroundStyle(Color.accentColor)
            // The row only exists while the undo window is open, so ⌘Z rides
            // with it — system undo muscle memory restores the slip.
            .keyboardShortcut("z", modifiers: .command)
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
                    HStack(spacing: SageDesign.Spacing.labelGap) {
                        Image(systemName: suggestion.systemImage)
                            .sageFont(type.icon, weight: .semibold)
                            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                        Text(suggestion.title)
                            .sageFont(type.body, weight: .medium)
                        Spacer(minLength: SageDesign.Spacing.small)
                        if !suggestion.description.isEmpty {
                            Text(suggestion.description)
                                .sageMicro(type.micro)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, SageDesign.Spacing.chipHorizontal)
                    .padding(.vertical, SageDesign.Spacing.chipVertical)
                    .background(
                        isSelected
                            ? Color.accentColor.opacity(SageDesign.Chrome.selectionFillOpacity)
                            : Color.clear
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
