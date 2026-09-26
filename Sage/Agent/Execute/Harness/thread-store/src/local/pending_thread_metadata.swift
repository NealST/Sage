//
//  pending_thread_metadata.swift
//  CodexThreadStore
//
//  Port of codex-rs/thread-store/src/local/pending_thread_metadata.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Tokio per-entry mutexes map to one `OSAllocatedUnfairLock` dictionary on
//  `LocalThreadStore`. The Rust `state_db` gate is skipped (GRDB is not
//  wired); the in-process registry is always available. `rollout_path`
//  rejection still happens on `LocalThreadStore.stagePendingThreadMetadata`.
//

import CodexProtocol
import Foundation
import os

/// In-memory metadata staged before a reserved thread starts.
final class PendingThreadMetadataRegistry: @unchecked Sendable {
    private let entries = OSAllocatedUnfairLock<[ThreadId: ThreadMetadataPatch]>(initialState: [:])

    func stage(threadId: ThreadId, patch: ThreadMetadataPatch) throws {
        if patch.isEmpty() {
            throw ThreadStoreError.invalidRequest(
                "pending thread metadata cannot be empty")
        }
        try entries.withLock { map in
            if map[threadId] != nil {
                throw ThreadStoreError.invalidRequest(
                    "pending thread metadata already exists: \(threadId)")
            }
            map[threadId] = patch
        }
    }

    func remove(threadId: ThreadId) {
        entries.withLock { $0.removeValue(forKey: threadId) }
    }

    func read(threadId: ThreadId) -> ThreadMetadataPatch? {
        entries.withLock { $0[threadId] }
    }
}
