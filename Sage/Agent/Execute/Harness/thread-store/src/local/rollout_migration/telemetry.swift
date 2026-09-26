//
//  telemetry.swift
//  CodexThreadStore
//
//  Port of codex-rs/thread-store/src/local/rollout_migration/telemetry.rs
//  (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Outcome aggregation and tag helpers are faithful. OpenTelemetry counters
//  / histograms are omitted until the otel crate is ported.
//

import Foundation

enum RolloutMigrationTrigger: Equatable, Sendable {
    case manual
    case startup

    var tag: String {
        switch self {
        case .manual: return "manual"
        case .startup: return "startup"
        }
    }
}

private enum RolloutMigrationScope: Equatable, Sendable {
    case all
    case selected

    var tag: String {
        switch self {
        case .all: return "all"
        case .selected: return "selected"
        }
    }
}

struct RolloutMigrationTelemetry {
    private let trigger: RolloutMigrationTrigger
    private let mode: RolloutMigrationMode
    private let scope: RolloutMigrationScope
    private let startedAt: Date

    init(trigger: RolloutMigrationTrigger, options: RolloutMigrationOptions) {
        self.trigger = trigger
        self.mode = options.mode
        self.scope = options.threadIds.isEmpty ? .all : .selected
        self.startedAt = Date()
    }

    func finish(_ result: Result<RolloutMigrationReport, ThreadStoreError>) {
        _ = (trigger, mode, scope, startedAt, result)
    }
}

extension RolloutMigrationMode {
    var tag: String {
        switch self {
        case .dryRun: return "dry_run"
        case .apply: return "apply"
        }
    }
}

extension RolloutMigrationStatus {
    var tag: String {
        switch self {
        case .eligible: return "eligible"
        case .migrated: return "migrated"
        case .alreadyPaginated: return "already_paginated"
        case .skippedEmpty: return "skipped_empty"
        case .skippedBusy: return "skipped_busy"
        case .failed: return "failed"
        }
    }
}

extension RolloutMigrationFailureReason {
    var tag: String {
        switch self {
        case .missingSqliteMetadata: return "missing_sqlite_metadata"
        case .invalidSessionMetadata: return "invalid_session_metadata"
        case .rolloutReadFailed: return "rollout_read_failed"
        case .legacyRolloutConversionFailed: return "legacy_rollout_conversion_failed"
        case .sqliteMaterializationFailed: return "sqlite_materialization_failed"
        case .rolloutPublishFailed: return "rollout_publish_failed"
        case .interruptedMigrationRecoveryFailed: return "interrupted_migration_recovery_failed"
        case .unknown: return "unknown"
        }
    }
}
