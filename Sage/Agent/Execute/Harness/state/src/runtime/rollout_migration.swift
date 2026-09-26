//
//  rollout_migration.swift
//  CodexState
//
//  Port of codex-rs/state/src/runtime/rollout_migration.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Cursor / skip-list SQL throws until a state pool exists. Method names
//  and record types match upstream.
//

import Foundation

extension StateRuntime {
    public func getRolloutMigrationState(
        migrationId: String
    ) async throws -> RolloutMigrationState? {
        _ = migrationId
        throw StateRuntimeError.sqliteUnavailable("state")
    }

    /// Advance one migration's checked frontier without letting concurrent
    /// startup checks move it backward.
    public func advanceRolloutMigrationState(
        migrationId: String,
        lastCheckedThread: RolloutMigrationCursor?
    ) async throws {
        _ = migrationId
        _ = lastCheckedThread
        throw StateRuntimeError.sqliteUnavailable("state")
    }

    public func listRolloutMigrationSkippedRollouts(
        migrationId: String
    ) async throws -> [RolloutMigrationSkippedRollout] {
        _ = migrationId
        throw StateRuntimeError.sqliteUnavailable("state")
    }

    public func recordRolloutMigrationSkip(
        migrationId: String,
        skippedRollout: RolloutMigrationSkippedRollout
    ) async throws {
        _ = migrationId
        _ = skippedRollout
        throw StateRuntimeError.sqliteUnavailable("state")
    }

    public func removeRolloutMigrationSkip(
        migrationId: String,
        rolloutPath: String
    ) async throws {
        _ = migrationId
        _ = rolloutPath
        throw StateRuntimeError.sqliteUnavailable("state")
    }
}
