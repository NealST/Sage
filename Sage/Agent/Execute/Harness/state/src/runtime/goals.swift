//
//  goals.swift
//  CodexState
//
//  Port of codex-rs/state/src/runtime/goals.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  SQLite methods throw until GRDB.
//

import CodexProtocol
import Foundation

public struct GoalUpdate: Equatable, Sendable {
    public var objective: String?
    public var status: ThreadGoalStatus?
    /// Nested optional matches upstream: `nil` = leave unchanged,
    /// `.some(nil)` = clear the budget, `.some(.some(n))` = set it.
    public var tokenBudget: Int64??
    public var expectedGoalId: String?

    public init(
        objective: String? = nil,
        status: ThreadGoalStatus? = nil,
        tokenBudget: Int64?? = nil,
        expectedGoalId: String? = nil
    ) {
        self.objective = objective
        self.status = status
        self.tokenBudget = tokenBudget
        self.expectedGoalId = expectedGoalId
    }
}

public enum GoalAccountingOutcome: Equatable, Sendable {
    case unchanged(ThreadGoal?)
    case updated(ThreadGoal)
}

public enum GoalAccountingMode: Equatable, Sendable {
    case activeStatusOnly
    case activeOnly
    case activeOrComplete
    case activeOrStopped
}

extension GoalStore {
    public func getThreadGoal(_ threadId: ThreadId) async throws -> ThreadGoal? {
        _ = threadId
        throw StateRuntimeError.sqliteUnavailable("goals")
    }

    public func replaceThreadGoalSnapshot(_ goal: ThreadGoal) async throws {
        _ = goal
        throw StateRuntimeError.sqliteUnavailable("goals")
    }

    public func hasThreadGoalContinuationDeferral(_ threadId: ThreadId) async throws -> Bool {
        _ = threadId
        throw StateRuntimeError.sqliteUnavailable("goals")
    }

    public func clearThreadGoalContinuationDeferral(_ threadId: ThreadId) async throws {
        _ = threadId
        throw StateRuntimeError.sqliteUnavailable("goals")
    }

    public func replaceThreadGoal(
        _ threadId: ThreadId,
        objective: String,
        status: ThreadGoalStatus,
        tokenBudget: Int64?
    ) async throws -> ThreadGoal {
        _ = threadId
        _ = objective
        _ = statusAfterBudgetLimit(status, tokensUsed: 0, tokenBudget: tokenBudget)
        throw StateRuntimeError.sqliteUnavailable("goals")
    }

    public func insertThreadGoal(
        _ threadId: ThreadId,
        objective: String,
        status: ThreadGoalStatus,
        tokenBudget: Int64?
    ) async throws -> ThreadGoal? {
        _ = threadId
        _ = objective
        _ = statusAfterBudgetLimit(status, tokensUsed: 0, tokenBudget: tokenBudget)
        throw StateRuntimeError.sqliteUnavailable("goals")
    }

    public func updateThreadGoal(
        _ threadId: ThreadId,
        update: GoalUpdate
    ) async throws -> ThreadGoal? {
        _ = threadId
        _ = update
        throw StateRuntimeError.sqliteUnavailable("goals")
    }

    public func pauseActiveThreadGoal(_ threadId: ThreadId) async throws -> ThreadGoal? {
        try await updateActiveThreadGoalStatus(threadId, status: .paused)
    }

    public func usageLimitActiveThreadGoal(_ threadId: ThreadId) async throws -> ThreadGoal? {
        try await updateActiveThreadGoalStatus(threadId, status: .usageLimited)
    }

    public func deleteThreadGoal(_ threadId: ThreadId) async throws -> ThreadGoal? {
        _ = threadId
        throw StateRuntimeError.sqliteUnavailable("goals")
    }

    public func accountThreadGoalUsage(
        _ threadId: ThreadId,
        timeDeltaSeconds: Int64,
        tokenDelta: Int64,
        mode: GoalAccountingMode,
        expectedGoalId: String?
    ) async throws -> GoalAccountingOutcome {
        let timeDeltaSeconds = max(timeDeltaSeconds, 0)
        let tokenDelta = max(tokenDelta, 0)
        if timeDeltaSeconds == 0 && tokenDelta == 0 {
            return .unchanged(try await getThreadGoal(threadId))
        }
        _ = mode
        _ = expectedGoalId
        throw StateRuntimeError.sqliteUnavailable("goals")
    }

    func updateActiveThreadGoalStatus(
        _ threadId: ThreadId,
        status: ThreadGoalStatus
    ) async throws -> ThreadGoal? {
        _ = threadId
        _ = status
        throw StateRuntimeError.sqliteUnavailable("goals")
    }
}

func statusAfterBudgetLimit(
    _ status: ThreadGoalStatus,
    tokensUsed: Int64,
    tokenBudget: Int64?
) -> ThreadGoalStatus {
    if status == .active, let budget = tokenBudget, tokensUsed >= budget {
        return .budgetLimited
    }
    return status
}
