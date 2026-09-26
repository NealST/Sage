//
//  backfill.swift
//  CodexState
//
//  Port of codex-rs/state/src/runtime/backfill.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  SQLite methods throw until a GRDB pool is attached. `ensureBackfillStateRow`
//  is the singleton-row repair used by every public backfill call.
//

import Foundation

extension StateRuntime {
    public func getBackfillState() async throws -> BackfillState {
        try await ensureBackfillStateRow()
        throw StateRuntimeError.sqliteUnavailable("backfill")
    }

    /// Attempt to claim ownership of rollout metadata backfill.
    ///
    /// Returns `true` when this runtime claimed the backfill worker slot.
    /// Returns `false` if backfill is already complete or currently owned by a
    /// non-expired worker.
    public func tryClaimBackfill(leaseSeconds: Int64) async throws -> Bool {
        try await ensureBackfillStateRow()
        _ = Date().timeIntervalSince1970
        _ = max(leaseSeconds, 0)
        throw StateRuntimeError.sqliteUnavailable("backfill")
    }

    /// Mark rollout metadata backfill as running.
    public func markBackfillRunning() async throws {
        try await ensureBackfillStateRow()
        throw StateRuntimeError.sqliteUnavailable("backfill")
    }

    /// Persist rollout metadata backfill progress.
    public func checkpointBackfill(watermark: String) async throws {
        try await ensureBackfillStateRow()
        _ = watermark
        throw StateRuntimeError.sqliteUnavailable("backfill")
    }

    /// Mark rollout metadata backfill as complete.
    public func markBackfillComplete(lastWatermark: String? = nil) async throws {
        try await ensureBackfillStateRow()
        _ = lastWatermark
        throw StateRuntimeError.sqliteUnavailable("backfill")
    }

    func ensureBackfillStateRow() async throws {
        throw StateRuntimeError.sqliteUnavailable("backfill")
    }
}
