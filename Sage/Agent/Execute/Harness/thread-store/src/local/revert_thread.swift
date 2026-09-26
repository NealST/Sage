//
//  revert_thread.swift
//  CodexThreadStore
//
//  Port of codex-rs/thread-store/src/local/revert_thread.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Revert is not JSONL truncation. Rust writes a new immutable rollout and
//  CAS-updates the SQLite rollout-path pointer. Without GRDB / writer-lock
//  coordinators / history materialization this throws
//  `unsupported("revert_thread")`. `LocalThreadStore.revertThread` keeps
//  the protocol default.
//

import CodexProtocol
import Foundation

func revert(
    store: LocalThreadStore,
    params: RevertThreadParams
) throws {
    _ = (store, params)
    throw ThreadStoreError.unsupported(operation: "revert_thread")
}
