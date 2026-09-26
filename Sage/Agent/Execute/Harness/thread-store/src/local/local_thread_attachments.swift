//
//  local_thread_attachments.swift
//  CodexThreadStore
//
//  Port of codex-rs/thread-store/src/local/thread_attachments.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Filename is `local_thread_attachments.swift` so SPM object-file basenames
//  do not collide with `thread-store/src/thread_attachments.swift`.
//  Attachment CRUD and copy share lifecycle exclusion with deletion in Rust
//  (`live_writer_locks` + state-db). Without GRDB every operation throws
//  `unsupported`. `InMemoryThreadStore` already implements the catalog.
//

import CodexProtocol
import Foundation

func copyThreadAttachments(
    store: LocalThreadStore,
    sourceThreadId: ThreadId,
    destinationThreadId: ThreadId
) throws {
    _ = (sourceThreadId, destinationThreadId)
    throw unsupportedAttachment(store, operation: "copy_thread_attachments")
}

func addThreadAttachment(
    store: LocalThreadStore,
    params: AddThreadAttachmentParams
) throws -> AddThreadAttachmentOutcome {
    _ = params
    throw unsupportedAttachment(store, operation: "thread/attachment/add")
}

func listThreadAttachments(
    store: LocalThreadStore,
    params: ListThreadAttachmentsParams
) throws -> ThreadAttachmentPage {
    _ = params
    throw unsupportedAttachment(store, operation: "thread/attachment/list")
}

func removeThreadAttachment(
    store: LocalThreadStore,
    params: RemoveThreadAttachmentParams
) throws -> RemoveThreadAttachmentOutcome {
    _ = params
    throw unsupportedAttachment(store, operation: "thread/attachment/remove")
}

private func unsupportedAttachment(
    _ store: LocalThreadStore,
    operation: String
) -> ThreadStoreError {
    _ = store
    return .unsupported(operation: operation)
}
