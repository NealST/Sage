//
//  thread_goal.swift
//  CodexState
//
//  Port of codex-rs/state/src/model/thread_goal.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  sqlx row mapping is omitted. `DateTime<Utc>` maps to `Date`.
//

import CodexProtocol
import Foundation

public enum ThreadGoalStatus: String, Codable, Equatable, Sendable {
    case active
    case paused
    case blocked
    case usageLimited = "usage_limited"
    case budgetLimited = "budget_limited"
    case complete

    public var asStr: String { rawValue }

    public var isActive: Bool { self == .active }

    public var isTerminal: Bool {
        self == .budgetLimited || self == .complete
    }

    public static func parse(_ value: String) throws -> ThreadGoalStatus {
        guard let status = ThreadGoalStatus(rawValue: value) else {
            throw StateModelError("unknown thread goal status `\(value)`")
        }
        return status
    }
}

public struct ThreadGoal: Codable, Equatable, Sendable {
    public var threadId: ThreadId
    public var goalId: String
    public var objective: String
    public var status: ThreadGoalStatus
    public var tokenBudget: Int64?
    public var tokensUsed: Int64
    public var timeUsedSeconds: Int64
    public var createdAt: Date
    public var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case threadId = "thread_id"
        case goalId = "goal_id"
        case objective, status
        case tokenBudget = "token_budget"
        case tokensUsed = "tokens_used"
        case timeUsedSeconds = "time_used_seconds"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public init(
        threadId: ThreadId,
        goalId: String,
        objective: String,
        status: ThreadGoalStatus,
        tokenBudget: Int64? = nil,
        tokensUsed: Int64,
        timeUsedSeconds: Int64,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.threadId = threadId
        self.goalId = goalId
        self.objective = objective
        self.status = status
        self.tokenBudget = tokenBudget
        self.tokensUsed = tokensUsed
        self.timeUsedSeconds = timeUsedSeconds
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        threadId = try container.decode(ThreadId.self, forKey: .threadId)
        goalId = try container.decode(String.self, forKey: .goalId)
        objective = try container.decode(String.self, forKey: .objective)
        status = try container.decode(ThreadGoalStatus.self, forKey: .status)
        tokenBudget = try container.decodeIfPresent(Int64.self, forKey: .tokenBudget)
        tokensUsed = try container.decode(Int64.self, forKey: .tokensUsed)
        timeUsedSeconds = try container.decode(Int64.self, forKey: .timeUsedSeconds)
        createdAt = try stateDecodeRFC3339(try container.decode(String.self, forKey: .createdAt))
        updatedAt = try stateDecodeRFC3339(try container.decode(String.self, forKey: .updatedAt))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(threadId, forKey: .threadId)
        try container.encode(goalId, forKey: .goalId)
        try container.encode(objective, forKey: .objective)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(tokenBudget, forKey: .tokenBudget)
        try container.encode(tokensUsed, forKey: .tokensUsed)
        try container.encode(timeUsedSeconds, forKey: .timeUsedSeconds)
        try container.encode(stateEncodeRFC3339(createdAt), forKey: .createdAt)
        try container.encode(stateEncodeRFC3339(updatedAt), forKey: .updatedAt)
    }

    init(row: ThreadGoalRow) throws {
        threadId = try ThreadId.fromString(row.threadId)
        goalId = row.goalId
        objective = row.objective
        status = try ThreadGoalStatus.parse(row.status)
        tokenBudget = row.tokenBudget
        tokensUsed = row.tokensUsed
        timeUsedSeconds = row.timeUsedSeconds
        createdAt = try epochMillisToDatetime(row.createdAtMs)
        updatedAt = try epochMillisToDatetime(row.updatedAtMs)
    }
}

struct ThreadGoalRow: Equatable, Sendable {
    var threadId: String
    var goalId: String
    var objective: String
    var status: String
    var tokenBudget: Int64?
    var tokensUsed: Int64
    var timeUsedSeconds: Int64
    var createdAtMs: Int64
    var updatedAtMs: Int64
}
