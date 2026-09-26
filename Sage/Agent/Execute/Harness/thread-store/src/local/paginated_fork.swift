//
//  paginated_fork.swift
//  CodexThreadStore
//
//  Port of codex-rs/thread-store/src/local/paginated_fork.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  `prepare` and `history_base_at_boundary` need live-writer lifecycle
//  locks, `thread_history` turn lookup, and SQLite projection state.
//  Those modules are not ported, so both entry points throw
//  `unsupported("prepare_fork")`. `loadForFork` in model_context.swift
//  is the JSONL helper this file would call once history materialization
//  lands. `LocalThreadStore.prepareFork` keeps the protocol default.
//

import CodexProtocol
import Foundation

func prepare(
    store: LocalThreadStore,
    params: PrepareForkParams
) throws -> PreparedFork {
    _ = (store, params)
    throw ThreadStoreError.unsupported(operation: "prepare_fork")
}

func historyBaseAtBoundary(
    store: LocalThreadStore,
    threadId: ThreadId,
    boundary: ForkBoundary,
    lineage: RolloutLineage
) throws -> HistoryPosition? {
    _ = (store, threadId, boundary, lineage)
    throw ThreadStoreError.unsupported(operation: "prepare_fork")
}

func missingTurnPosition(_ turnId: String) -> ThreadStoreError {
    .invalidRequest("turn \(turnId) does not have persisted rollout positions")
}

func invalidTurnPosition(_ turnId: String) -> ThreadStoreError {
    .internal("invalid rollout position for turn \(turnId)")
}
