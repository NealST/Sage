//
//  memories.swift
//  CodexState
//
//  Port of codex-rs/state/src/model/memories.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  `PathBuf` maps to `String`. `DateTime<Utc>` maps to `Date`.
//

import CodexProtocol
import Foundation

/// Stored stage-1 memory extraction output for a single thread.
public struct Stage1Output: Codable, Equatable, Sendable {
    public var threadId: ThreadId
    public var rolloutPath: String
    public var sourceUpdatedAt: Date
    public var rawMemory: String
    public var rolloutSummary: String
    public var rolloutSlug: String?
    public var cwd: String
    public var gitBranch: String?
    public var generatedAt: Date

    enum CodingKeys: String, CodingKey {
        case threadId = "thread_id"
        case rolloutPath = "rollout_path"
        case sourceUpdatedAt = "source_updated_at"
        case rawMemory = "raw_memory"
        case rolloutSummary = "rollout_summary"
        case rolloutSlug = "rollout_slug"
        case cwd
        case gitBranch = "git_branch"
        case generatedAt = "generated_at"
    }

    public init(
        threadId: ThreadId,
        rolloutPath: String,
        sourceUpdatedAt: Date,
        rawMemory: String,
        rolloutSummary: String,
        rolloutSlug: String? = nil,
        cwd: String,
        gitBranch: String? = nil,
        generatedAt: Date
    ) {
        self.threadId = threadId
        self.rolloutPath = rolloutPath
        self.sourceUpdatedAt = sourceUpdatedAt
        self.rawMemory = rawMemory
        self.rolloutSummary = rolloutSummary
        self.rolloutSlug = rolloutSlug
        self.cwd = cwd
        self.gitBranch = gitBranch
        self.generatedAt = generatedAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        threadId = try container.decode(ThreadId.self, forKey: .threadId)
        rolloutPath = try container.decode(String.self, forKey: .rolloutPath)
        sourceUpdatedAt = try stateDecodeRFC3339(try container.decode(String.self, forKey: .sourceUpdatedAt))
        rawMemory = try container.decode(String.self, forKey: .rawMemory)
        rolloutSummary = try container.decode(String.self, forKey: .rolloutSummary)
        rolloutSlug = try container.decodeIfPresent(String.self, forKey: .rolloutSlug)
        cwd = try container.decode(String.self, forKey: .cwd)
        gitBranch = try container.decodeIfPresent(String.self, forKey: .gitBranch)
        generatedAt = try stateDecodeRFC3339(try container.decode(String.self, forKey: .generatedAt))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(threadId, forKey: .threadId)
        try container.encode(rolloutPath, forKey: .rolloutPath)
        try container.encode(stateEncodeRFC3339(sourceUpdatedAt), forKey: .sourceUpdatedAt)
        try container.encode(rawMemory, forKey: .rawMemory)
        try container.encode(rolloutSummary, forKey: .rolloutSummary)
        try container.encodeIfPresent(rolloutSlug, forKey: .rolloutSlug)
        try container.encode(cwd, forKey: .cwd)
        try container.encodeIfPresent(gitBranch, forKey: .gitBranch)
        try container.encode(stateEncodeRFC3339(generatedAt), forKey: .generatedAt)
    }
}

/// Result of trying to claim a stage-1 memory extraction job.
public enum Stage1JobClaimOutcome: Codable, Equatable, Sendable {
    /// The caller owns the job and should continue with extraction.
    case claimed(ownershipToken: String)
    /// Existing output is already newer than or equal to the source rollout.
    case skippedUpToDate
    /// Another worker currently owns a fresh lease for this job.
    case skippedRunning
    /// The job is in backoff and should not be retried yet.
    case skippedRetryBackoff
    /// The job has exhausted retries and should not be retried automatically.
    case skippedRetryExhausted
}

/// Claimed stage-1 job with thread metadata.
public struct Stage1JobClaim: Codable, Equatable, Sendable {
    public var thread: ThreadMetadata
    public var ownershipToken: String

    enum CodingKeys: String, CodingKey {
        case thread
        case ownershipToken = "ownership_token"
    }

    public init(thread: ThreadMetadata, ownershipToken: String) {
        self.thread = thread
        self.ownershipToken = ownershipToken
    }
}

public struct Stage1StartupClaimParams: Equatable, Sendable {
    public var scanLimit: Int
    public var maxClaimed: Int
    public var maxAgeDays: Int64
    public var minRolloutIdleHours: Int64
    public var allowedSources: [String]
    public var leaseSeconds: Int64

    public init(
        scanLimit: Int,
        maxClaimed: Int,
        maxAgeDays: Int64,
        minRolloutIdleHours: Int64,
        allowedSources: [String],
        leaseSeconds: Int64
    ) {
        self.scanLimit = scanLimit
        self.maxClaimed = maxClaimed
        self.maxAgeDays = maxAgeDays
        self.minRolloutIdleHours = minRolloutIdleHours
        self.allowedSources = allowedSources
        self.leaseSeconds = leaseSeconds
    }
}

/// Result of trying to claim a phase-2 consolidation job.
public enum Phase2JobClaimOutcome: Codable, Equatable, Sendable {
    /// The caller owns the global lock and may inspect the memory workspace.
    case claimed(ownershipToken: String, inputWatermark: Int64)
    /// The global job is in retry backoff.
    case skippedRetryUnavailable
    /// The global job completed recently enough that consolidation is cooling down.
    case skippedCooldown
    /// Another worker currently owns a fresh global consolidation lease.
    case skippedRunning
}
