//
//  thread_attachments.swift
//  CodexState
//
//  Port of codex-rs/state/src/runtime/thread_attachments.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Attachment CRUD SQL throws until a state pool exists. Identity, payload
//  size, page-limit, and cursor checks run in memory first.
//

import CodexProtocol
import Foundation

extension StateRuntime {
    /// Atomically copies current membership into a new, empty fork, independent of history cutoffs.
    public func copyThreadAttachments(
        sourceThreadId: ThreadId,
        destinationThreadId: ThreadId
    ) async throws {
        _ = sourceThreadId
        _ = destinationThreadId
        throw StateRuntimeError.sqliteUnavailable("thread_attachments")
    }

    /// Attach an attachment once, returning an existing attachment for repeated requests.
    public func addThreadAttachment(
        threadId: ThreadId,
        attachmentType: String,
        identityKey: String,
        payload: JSONValue
    ) async throws -> AddThreadAttachmentOutcome {
        try validateAttachmentIdentity(attachmentType: attachmentType, identityKey: identityKey)
        let serializedPayload = payload.encodedString()
        if serializedPayload.utf8.count > MAX_THREAD_ATTACHMENT_PAYLOAD_BYTES {
            throw StateRuntimeError.invalidInput(
                "invalid thread attachment request: attachment payload exceeds \(MAX_THREAD_ATTACHMENT_PAYLOAD_BYTES) bytes"
            )
        }
        _ = threadId
        _ = MAX_THREAD_ATTACHMENTS_PER_THREAD
        throw StateRuntimeError.sqliteUnavailable("thread_attachments")
    }

    /// Remove an attached attachment, immediately freeing its slot.
    public func removeThreadAttachment(
        threadId: ThreadId,
        attachmentType: String,
        identityKey: String
    ) async throws -> RemoveThreadAttachmentOutcome {
        try validateAttachmentIdentity(attachmentType: attachmentType, identityKey: identityKey)
        _ = threadId
        throw StateRuntimeError.sqliteUnavailable("thread_attachments")
    }

    /// List one bounded page of attachments for one thread in stable keyset order.
    public func listThreadAttachments(
        threadId: ThreadId,
        cursor: String?,
        limit: Int
    ) async throws -> ThreadAttachmentPage {
        if !(1...MAX_THREAD_ATTACHMENT_LIST_PAGE_SIZE).contains(limit) {
            throw StateRuntimeError.invalidInput(
                "invalid thread attachment request: page limit must be between 1 and \(MAX_THREAD_ATTACHMENT_LIST_PAGE_SIZE)"
            )
        }
        if let cursor {
            let (cursorThreadId, _, _) = try parseAttachmentCursor(cursor)
            if cursorThreadId != threadId.description {
                throw StateRuntimeError.invalidInput(
                    "invalid thread attachment request: invalid pagination cursor"
                )
            }
        }
        throw StateRuntimeError.sqliteUnavailable("thread_attachments")
    }
}

func validateAttachmentIdentity(attachmentType: String, identityKey: String) throws {
    if attachmentType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        throw StateRuntimeError.invalidInput(
            "invalid thread attachment request: attachment type must not be empty"
        )
    }
    if attachmentType.utf8.count > MAX_THREAD_ATTACHMENT_TYPE_BYTES {
        throw StateRuntimeError.invalidInput(
            "invalid thread attachment request: attachment type exceeds \(MAX_THREAD_ATTACHMENT_TYPE_BYTES) bytes"
        )
    }
    if identityKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        throw StateRuntimeError.invalidInput(
            "invalid thread attachment request: attachment identity key must not be empty"
        )
    }
    if identityKey.utf8.count > MAX_THREAD_ATTACHMENT_IDENTITY_KEY_BYTES {
        throw StateRuntimeError.invalidInput(
            "invalid thread attachment request: attachment identity key exceeds \(MAX_THREAD_ATTACHMENT_IDENTITY_KEY_BYTES) bytes"
        )
    }
}

func parseAttachmentCursor(_ cursor: String) throws -> (String, Int64, String) {
    let segments = cursor.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
    guard segments.count == 3 else {
        throw StateRuntimeError.invalidInput(
            "invalid thread attachment request: invalid pagination cursor"
        )
    }
    let threadId = segments[0]
    let createdAtText = segments[1]
    let attachmentId = segments[2]
    do {
        _ = try ThreadId.fromString(threadId)
        guard UUID(uuidString: attachmentId) != nil else {
            throw StateRuntimeError.invalidInput(
                "invalid thread attachment request: invalid pagination cursor"
            )
        }
        guard let createdAt = Int64(createdAtText) else {
            throw StateRuntimeError.invalidInput(
                "invalid thread attachment request: invalid pagination cursor"
            )
        }
        return (threadId, createdAt, attachmentId)
    } catch is StateRuntimeError {
        throw StateRuntimeError.invalidInput(
            "invalid thread attachment request: invalid pagination cursor"
        )
    } catch {
        throw StateRuntimeError.invalidInput(
            "invalid thread attachment request: invalid pagination cursor"
        )
    }
}
