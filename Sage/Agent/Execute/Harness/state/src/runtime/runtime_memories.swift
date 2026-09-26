//
//  runtime_memories.swift
//  CodexState
//
//  Port of codex-rs/state/src/runtime/memories.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  SQLite methods throw until GRDB.
//

import CodexProtocol
import Foundation

let JOB_KIND_MEMORY_STAGE1 = "memory_stage1"
let JOB_KIND_MEMORY_CONSOLIDATE_GLOBAL = "memory_consolidate_global"
let MEMORY_CONSOLIDATION_JOB_KEY = "global"
let PHASE2_SUCCESS_COOLDOWN_SECONDS: Int64 = 6 * 60 * 60
let PHASE2_INPUT_SELECTION_PAGE_SIZE = 512
let DEFAULT_RETRY_REMAINING: Int64 = 3

extension MemoryStore {
    /// Record usage for cited stage-1 outputs.
    ///
    /// Each thread id increments `usage_count` by one and sets `last_usage` to
    /// the current Unix timestamp. Missing rows are ignored.
    public func recordStage1OutputUsage(_ threadIds: [ThreadId]) async throws -> Int {
        if threadIds.isEmpty {
            return 0
        }
        throw StateRuntimeError.sqliteUnavailable("memories")
    }

    /// Selects and claims stage-1 startup jobs for stale threads.
    public func claimStage1JobsForStartup(
        _ currentThreadId: ThreadId,
        params: Stage1StartupClaimParams
    ) async throws -> [Stage1JobClaim] {
        if params.scanLimit == 0 || params.maxClaimed == 0 {
            return []
        }
        _ = currentThreadId
        throw StateRuntimeError.sqliteUnavailable("memories")
    }

    /// Lists the newest visible stage-1 outputs eligible for global consolidation.
    public func listStage1OutputsForGlobal(_ n: Int) async throws -> [Stage1Output] {
        if n == 0 {
            return []
        }
        throw StateRuntimeError.sqliteUnavailable("memories")
    }

    /// Prunes stale stage-1 outputs while preserving the latest phase-2
    /// baseline and stage-1 job watermarks.
    public func pruneStage1OutputsForRetention(
        maxUnusedDays: Int64,
        limit: Int
    ) async throws -> Int {
        if limit == 0 {
            return 0
        }
        _ = maxUnusedDays
        throw StateRuntimeError.sqliteUnavailable("memories")
    }

    /// Returns the current phase-2 input set.
    public func getPhase2InputSelection(
        _ n: Int,
        maxUnusedDays: Int64
    ) async throws -> [Stage1Output] {
        if n == 0 {
            return []
        }
        _ = maxUnusedDays
        _ = PHASE2_INPUT_SELECTION_PAGE_SIZE
        throw StateRuntimeError.sqliteUnavailable("memories")
    }

    /// Marks a thread as polluted and enqueues phase-2 forgetting when the
    /// thread participated in the last successful phase-2 baseline.
    public func markThreadMemoryModePolluted(_ threadId: ThreadId) async throws -> Bool {
        _ = threadId
        throw StateRuntimeError.sqliteUnavailable("memories")
    }

    /// Attempts to claim a stage-1 job for a thread at `sourceUpdatedAt`.
    public func tryClaimStage1Job(
        threadId: ThreadId,
        workerId: ThreadId,
        sourceUpdatedAt: Int64,
        leaseSeconds: Int64,
        maxRunningJobs: Int
    ) async throws -> Stage1JobClaimOutcome {
        _ = threadId
        _ = workerId
        _ = sourceUpdatedAt
        _ = leaseSeconds
        _ = maxRunningJobs
        _ = JOB_KIND_MEMORY_STAGE1
        throw StateRuntimeError.sqliteUnavailable("memories")
    }

    /// Marks a claimed stage-1 job successful and upserts the extracted output.
    public func markStage1JobSucceeded(
        threadId: ThreadId,
        ownershipToken: String,
        sourceUpdatedAt: Int64,
        rawMemory: String,
        rolloutSummary: String,
        rolloutSlug: String?
    ) async throws -> Bool {
        _ = threadId
        _ = ownershipToken
        _ = sourceUpdatedAt
        _ = rawMemory
        _ = rolloutSummary
        _ = rolloutSlug
        throw StateRuntimeError.sqliteUnavailable("memories")
    }

    /// Marks a claimed stage-1 job successful when extraction produced no output.
    public func markStage1JobSucceededNoOutput(
        threadId: ThreadId,
        ownershipToken: String
    ) async throws -> Bool {
        _ = threadId
        _ = ownershipToken
        throw StateRuntimeError.sqliteUnavailable("memories")
    }

    /// Marks a claimed stage-1 job as failed and schedules retry backoff.
    public func markStage1JobFailed(
        threadId: ThreadId,
        ownershipToken: String,
        failureReason: String,
        retryDelaySeconds: Int64
    ) async throws -> Bool {
        _ = threadId
        _ = ownershipToken
        _ = failureReason
        _ = retryDelaySeconds
        throw StateRuntimeError.sqliteUnavailable("memories")
    }

    /// Enqueues or advances the global phase-2 consolidation job watermark.
    public func enqueueGlobalConsolidation(_ inputWatermark: Int64) async throws {
        _ = inputWatermark
        _ = JOB_KIND_MEMORY_CONSOLIDATE_GLOBAL
        _ = MEMORY_CONSOLIDATION_JOB_KEY
        _ = DEFAULT_RETRY_REMAINING
        throw StateRuntimeError.sqliteUnavailable("memories")
    }

    /// Attempts to claim the global phase-2 consolidation lock.
    public func tryClaimGlobalPhase2Job(
        workerId: ThreadId,
        leaseSeconds: Int64
    ) async throws -> Phase2JobClaimOutcome {
        _ = workerId
        _ = leaseSeconds
        _ = PHASE2_SUCCESS_COOLDOWN_SECONDS
        throw StateRuntimeError.sqliteUnavailable("memories")
    }

    /// Extends the lease on an owned running global phase-2 job.
    public func heartbeatGlobalPhase2Job(
        ownershipToken: String,
        leaseSeconds: Int64
    ) async throws -> Bool {
        _ = ownershipToken
        _ = leaseSeconds
        throw StateRuntimeError.sqliteUnavailable("memories")
    }

    /// Marks the owned running global phase-2 job as succeeded.
    public func markGlobalPhase2JobSucceeded(
        ownershipToken: String,
        completedWatermark: Int64,
        selectedOutputs: [Stage1Output]
    ) async throws -> Bool {
        _ = ownershipToken
        _ = completedWatermark
        _ = selectedOutputs
        throw StateRuntimeError.sqliteUnavailable("memories")
    }

    /// Marks the owned running global phase-2 job as failed and schedules retry.
    public func markGlobalPhase2JobFailed(
        ownershipToken: String,
        failureReason: String,
        retryDelaySeconds: Int64
    ) async throws -> Bool {
        _ = ownershipToken
        _ = failureReason
        _ = retryDelaySeconds
        throw StateRuntimeError.sqliteUnavailable("memories")
    }

    /// Fallback failure finalization when ownership may have been lost.
    public func markGlobalPhase2JobFailedIfUnowned(
        ownershipToken: String,
        failureReason: String,
        retryDelaySeconds: Int64
    ) async throws -> Bool {
        _ = ownershipToken
        _ = failureReason
        _ = retryDelaySeconds
        throw StateRuntimeError.sqliteUnavailable("memories")
    }
}
