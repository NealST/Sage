//
//  turn_lookup.swift
//  CodexThreadStore
//
//  Port of codex-rs/thread-store/src/local/thread_history/turn_lookup.rs
//  (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  `TurnRow` is ported. `findSourceTurn` / `findVisibleTurn` throw until
//  GRDB can query `thread_turns`. No schema is invented.
//

import CodexProtocol
import Foundation

struct TurnRow {
    var rolloutId: ThreadId
    var rolloutOrdinal: Int64
    var rolloutByteOffset: Int64?
    var rolloutEndOrdinal: Int64?
    var rolloutEndByteOffset: Int64?
    var status: String
    var firstUserItemId: String?
    var finalAgentItemId: String?
}

func findSourceTurn(
    lineage: RolloutLineage,
    turnId: String
) throws -> TurnRow {
    _ = (lineage, turnId)
    throw ThreadStoreError.internal(
        "failed to resolve logical turn: SQLite projection requires GRDB")
}

func findVisibleTurn(
    lineage: RolloutLineage,
    turnId: String
) throws -> TurnRow {
    _ = (lineage, turnId)
    throw ThreadStoreError.internal(
        "failed to resolve logical turn: SQLite projection requires GRDB")
}
