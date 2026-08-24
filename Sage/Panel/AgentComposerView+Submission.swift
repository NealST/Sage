//
//  AgentComposerView+Submission.swift
//  Sage
//
//  Composer submission and keyboard-driven suggestion actions.
//

import SwiftUI

extension AgentComposerView {
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
        slashSuggestions = []
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
        withAnimation(.easeOut(duration: 0.15)) { slashSuggestions = [] }
        return .handled
    }

    private func submit() {
        let trimmed = session.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachments = session.draftAttachments
        guard !trimmed.isEmpty || !attachments.isEmpty else { return }
        guard !blocksSubmit else { return }
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
        slashSuggestions = []
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
                isPreparingAttachments = false
                session.finishAttachmentSubmission(
                    attachments,
                    accepted: false,
                    startingRevision: submissionRevision
                )
                showPersistentAttachmentHint(
                    "Couldn’t prepare for vision: "
                    + failedImages.map(\.displayName).joined(separator: ", ")
                    + "."
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
}
