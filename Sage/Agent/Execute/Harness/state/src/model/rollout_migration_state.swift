//
//  rollout_migration_state.swift
//  CodexState
//
//  Port of codex-rs/state/src/model/rollout_migration_state.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  sqlx row mapping is omitted. These types stay generic bookkeeping records.
//

import Foundation

/// Creation-ordered thread frontier checked by one rollout migration.
public struct RolloutMigrationCursor: Codable, Equatable, Sendable, Comparable {
    public var threadCreatedAt: Int64
    public var threadId: String

    enum CodingKeys: String, CodingKey {
        case threadCreatedAt = "thread_created_at"
        case threadId = "thread_id"
    }

    public init(threadCreatedAt: Int64, threadId: String) {
        self.threadCreatedAt = threadCreatedAt
        self.threadId = threadId
    }

    public static func < (lhs: RolloutMigrationCursor, rhs: RolloutMigrationCursor) -> Bool {
        if lhs.threadCreatedAt != rhs.threadCreatedAt {
            return lhs.threadCreatedAt < rhs.threadCreatedAt
        }
        return lhs.threadId < rhs.threadId
    }
}

/// Persisted progress for one rollout migration.
public struct RolloutMigrationState: Codable, Equatable, Sendable {
    public var lastCheckedThread: RolloutMigrationCursor?

    enum CodingKeys: String, CodingKey {
        case lastCheckedThread = "last_checked_thread"
    }

    public init(lastCheckedThread: RolloutMigrationCursor? = nil) {
        self.lastCheckedThread = lastCheckedThread
    }
}

/// An unchanged rollout that one migration can safely skip.
public struct RolloutMigrationSkippedRollout: Codable, Equatable, Sendable {
    public var rolloutPath: String
    public var rolloutSizeBytes: Int64
    public var rolloutModifiedAtNs: Int64
    public var skipReason: String

    enum CodingKeys: String, CodingKey {
        case rolloutPath = "rollout_path"
        case rolloutSizeBytes = "rollout_size_bytes"
        case rolloutModifiedAtNs = "rollout_modified_at_ns"
        case skipReason = "skip_reason"
    }

    public init(
        rolloutPath: String,
        rolloutSizeBytes: Int64,
        rolloutModifiedAtNs: Int64,
        skipReason: String
    ) {
        self.rolloutPath = rolloutPath
        self.rolloutSizeBytes = rolloutSizeBytes
        self.rolloutModifiedAtNs = rolloutModifiedAtNs
        self.skipReason = skipReason
    }
}
