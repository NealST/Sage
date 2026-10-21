//
//  AgentComposerView+Attachments.swift
//  Sage
//
//  Attachment selection, import, preview, and removal for the composer.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension AgentComposerView {
    func pickAttachments() {
        guard !blocksTyping else { return }
        guard let outcome = AttachmentImport.pickFromOpenPanel(
            policy: pathGuardPolicy,
            into: session.draftAttachments
        ) else { return }
        applyImport(outcome)
    }

    func handlePasteboard() -> Bool {
        guard !blocksTyping else { return false }
        guard AttachmentImport.pasteboardHasNonTextPayload() else { return false }
        Task { await applyPasteboard() }
        return true
    }

    private func applyPasteboard() async {
        let revision = session.composerRevision
        attachmentImportCount += 1
        defer { attachmentImportCount -= 1 }
        guard let outcome = await AttachmentImport.fromPasteboard(into: []) else { return }
        mergeImportedOutcome(outcome, revision: revision)
    }

    func applyDrop(_ providers: [NSItemProvider]) async {
        guard !blocksTyping else { return }
        let revision = session.composerRevision
        attachmentImportCount += 1
        defer { attachmentImportCount -= 1 }
        let outcome = await AttachmentImport.fromItemProviders(
            providers,
            into: []
        )
        mergeImportedOutcome(outcome, revision: revision)
    }

    private func mergeImportedOutcome(
        _ outcome: AttachmentImportOutcome,
        revision: UInt
    ) {
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
        attachmentHintGeneration &+= 1
        session.attachmentHint = outcome.hint
        if outcome.hint != nil {
            let generation = attachmentHintGeneration
            Task {
                try? await Task.sleep(for: .seconds(4))
                if attachmentHintGeneration == generation {
                    session.attachmentHint = nil
                }
            }
        }
    }

    func showPersistentAttachmentHint(_ hint: String) {
        attachmentHintGeneration &+= 1
        session.attachmentHint = hint
    }

    func dismissAttachmentHint() {
        attachmentHintGeneration &+= 1
        session.attachmentHint = nil
    }

    func selectAttachment(_ attachment: MessageAttachment) {
        guard let index = session.draftAttachments.firstIndex(where: { $0.id == attachment.id })
        else { return }
        QuickLookPresenter.shared.preview(
            urls: session.draftAttachments.map(\.fileURL),
            selectedIndex: index
        )
    }

    func removeAttachment(_ attachment: MessageAttachment) {
        guard let index = session.draftAttachments.firstIndex(where: { $0.id == attachment.id })
        else { return }
        // A previous removal still in its undo window loses the window —
        // only one level of undo, so its managed copies are reclaimed now.
        commitAttachmentRemoval()
        session.draftAttachments.remove(at: index)
        removedAttachment = attachment
        removedAttachmentIndex = index
        if session.draftAttachments.count < MessageAttachment.maxCount,
           session.attachmentHint == AttachmentImport.tooManyHint {
            session.attachmentHint = nil
        }
        attachmentRemovalTask?.cancel()
        attachmentRemovalTask = Task { [weak session] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            if session?.draftAttachments.contains(where: { $0.id == attachment.id }) != true {
                commitAttachmentRemoval()
            }
        }
    }

    func undoAttachmentRemoval() {
        attachmentRemovalTask?.cancel()
        attachmentRemovalTask = nil
        guard let attachment = removedAttachment else { return }
        withAnimation(SageDesign.Motion.expandAnimation) {
            if let index = removedAttachmentIndex,
               index <= session.draftAttachments.count {
                session.draftAttachments.insert(attachment, at: index)
            } else {
                session.draftAttachments.append(attachment)
            }
            removedAttachment = nil
            removedAttachmentIndex = nil
        }
    }

    /// Undo window closed — the managed copies can finally be reclaimed.
    /// Also called from `submit()` so a sent turn never drags a pending
    /// removal along.
    func commitAttachmentRemoval() {
        attachmentRemovalTask?.cancel()
        attachmentRemovalTask = nil
        guard let attachment = removedAttachment else { return }
        MessageAttachment.deleteManagedCopies([attachment])
        removedAttachment = nil
        removedAttachmentIndex = nil
    }
}
