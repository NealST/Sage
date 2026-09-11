//
//  AgentComposerView+Submission.swift
//  Sage
//
//  Composer submission and keyboard-driven suggestion actions.
//

import SwiftUI

extension AgentComposerView {
    var pendingConfirmationHint: String {
        switch session.agent.turnChrome {
        case .toolRoundLimit:
            return "Continue for more tool rounds, or finish"

        case .toolApproval:
            return "Allow, skip, or stop this tool"

        case .reviewFailed:
            return "Retry review, or use the current reply"

        case .reviewMustFix:
            return "Continue fixing these issues, or keep this reply"

        case .reviewOptional:
            return "Improve these, or keep this reply"

        default:
            return "Run or Cancel the pending plan"
        }
    }

    var turnInterruptPresented: Binding<Bool> {
        Binding(
            get: { session.agent.state.turnInput.hasOffer },
            set: { presented in
                if !presented, session.agent.state.turnInput.hasOffer {
                    restoreTurnInterruptDraft()
                }
            }
        )
    }

    var composerPlaceholder: String {
        if case .awaitingConfirmation = session.agent.state.phase {
            return "Ask Sage…"
        }
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
        return "Ask Sage… (type / for commands)"
    }

    func restoreTurnInterruptDraft() {
        guard let offer = session.agent.state.turnInput.offer else { return }
        session.draft = offer.text
        session.draftAttachments = offer.attachments
        session.agent.dismissTurnInterrupt()
    }

    var composerAccessibilityHint: String {
        if session.agent.shouldOfferTurnInterrupt {
            return "Press Return to send. Sage will ask whether to queue or redirect."
        }
        if session.agent.state.hasPendingPlan {
            return "Run, cancel, or retry the pending plan before sending"
        }
        if blocksTyping { return "Unavailable while Sage is working" }
        if !slashSuggestions.isEmpty {
            return "Use Up and Down arrows to choose a command, Return to select, Escape to dismiss"
        }
        return "Press Return to send. Command-Up recalls recent messages. Shift-Command-A adds files."
    }

    /// ⌘↑/⌘↓ recall. Positive `step` moves older, negative moves newer; the
    /// live draft is stashed on first recall and restored on the way back down.
    func recallInputHistory(_ step: Int) -> KeyPress.Result {
        let history = session.inputHistory
        guard !history.isEmpty else { return .ignored }
        let current = historyRecallIndex ?? -1
        if step < 0, current == -1 { return .ignored }
        if step > 0, historyRecallIndex == nil {
            liveDraftBeforeRecall = session.draft
        }
        let next = current + step
        if next < 0 {
            historyRecallIndex = nil
            session.draft = liveDraftBeforeRecall ?? ""
            liveDraftBeforeRecall = nil
        } else {
            let clamped = min(next, history.count - 1)
            historyRecallIndex = clamped
            session.draft = history[clamped]
        }
        return .handled
    }

    func handleComposerSubmit() {
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

    func applySuggestion(_ suggestion: ComposerSlashSuggestion) {
        session.draft = suggestion.insertDraft
        withAnimation(SageDesign.Motion.scrollAnimation) {
            slashSuggestions = []
        }
        if suggestion.submitOnSelect {
            submit()
        }
    }

    func moveSuggestionSelection(by delta: Int) -> KeyPress.Result {
        guard !slashSuggestions.isEmpty else { return .ignored }
        let count = slashSuggestions.count
        selectedSuggestionIndex = (selectedSuggestionIndex + delta + count) % count
        return .handled
    }

    func dismissSuggestionsIfNeeded() -> KeyPress.Result {
        guard !slashSuggestions.isEmpty else { return .ignored }
        withAnimation(SageDesign.Motion.scrollAnimation) { slashSuggestions = [] }
        return .handled
    }

    private func submit() {
        let trimmed = session.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachments = session.draftAttachments
        guard !trimmed.isEmpty || !attachments.isEmpty else { return }
        guard !blocksSubmit else { return }
        // A sent turn must not leave a pending removal holding managed files.
        commitAttachmentRemoval()
        if !attachments.isEmpty, trimmed.hasPrefix("/") {
            showPersistentAttachmentHint("Remove attachments before running a slash command.")
            return
        }
        let unavailable = attachments.filter { !$0.isAvailable }
        if !unavailable.isEmpty {
            let names = unavailable.map(\.displayName).joined(separator: ", ")
            showPersistentAttachmentHint(
                "Remove missing or unreadable attachments: \(names)."
            )
            return
        }
        stickToBottom = true
        withAnimation(SageDesign.Motion.scrollAnimation) {
            slashSuggestions = []
        }
        session.recordSubmittedInput(trimmed)
        historyRecallIndex = nil
        liveDraftBeforeRecall = nil
        session.agent.freezeConfirmationActions()
        isPreparingAttachments = true
        let submissionRevision = session.beginAttachmentSubmission(attachments)
        Task {
            let failedImages = await Task.detached(priority: .userInitiated) {
                attachments.filter { attachment in
                    attachment.kind == .image
                        && !AttachmentImageEncoder.canEncode(attachment.fileURL)
                }
            }.value
            guard failedImages.isEmpty else {
                abortFailedImagePreparation(
                    failedImages,
                    attachments: attachments,
                    startingRevision: submissionRevision
                )
                return
            }
            let accepted = await session.agent.submit(trimmed, attachments: attachments)
            isPreparingAttachments = false
            session.finishAttachmentSubmission(
                attachments,
                accepted: accepted,
                startingRevision: submissionRevision
            )
        }
    }

    private func abortFailedImagePreparation(
        _ failedImages: [MessageAttachment],
        attachments: [MessageAttachment],
        startingRevision: UInt
    ) {
        isPreparingAttachments = false
        session.agent.unfreezeConfirmationActions()
        session.finishAttachmentSubmission(
            attachments,
            accepted: false,
            startingRevision: startingRevision
        )
        showPersistentAttachmentHint(
            "Couldn’t prepare for vision: "
            + failedImages.map(\.displayName).joined(separator: ", ")
            + "."
        )
    }
}
