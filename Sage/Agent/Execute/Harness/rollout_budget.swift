//
//  rollout_budget.swift
//  CodexCore
//
//  Port of codex-rs/core/src/rollout_budget.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  `OnceLock<Mutex<>>` maps to `OSAllocatedUnfairLock` of an optional state.
//  `RolloutBudgetConfig` lives here so CodexCore does not depend on Sage Config.
//

import CodexProtocol
import Foundation
import os

public struct RolloutBudgetConfig: Equatable, Sendable {
    public var limitTokens: Int64
    public var samplingTokenWeight: Double
    public var prefillTokenWeight: Double
    public var reminderAtRemainingTokens: [Int64]

    public init(
        limitTokens: Int64,
        samplingTokenWeight: Double = 1,
        prefillTokenWeight: Double = 1,
        reminderAtRemainingTokens: [Int64] = []
    ) {
        self.limitTokens = limitTokens
        self.samplingTokenWeight = samplingTokenWeight
        self.prefillTokenWeight = prefillTokenWeight
        self.reminderAtRemainingTokens = reminderAtRemainingTokens
    }
}

/// Budget reminder returned by a controller and acknowledged after history insertion.
public struct RolloutBudgetReminder: Equatable, Sendable {
    public var remainingTokens: Int64
    /// Backend-defined reminder position, returned unchanged on acknowledgement.
    public var reminderIndex: Int64

    public init(remainingTokens: Int64, reminderIndex: Int64) {
        self.remainingTokens = remainingTokens
        self.reminderIndex = reminderIndex
    }
}

/// Shared accounting and reminder state for one root-thread session tree.
public final class RolloutBudget: @unchecked Sendable {
    private struct ThreadBudgetDelivery {
        var windowId: String
        var reminderIndex: Int64
    }

    private struct State {
        var config: RolloutBudgetConfig
        var weightedTokensUsed: Double
        var deliveries: [ThreadId: ThreadBudgetDelivery]
    }

    private let lock = OSAllocatedUnfairLock<State?>(initialState: nil)

    public init() {}

    public func configure(_ config: RolloutBudgetConfig) {
        lock.withLock { state in
            if state == nil {
                state = State(config: config, weightedTokensUsed: 0, deliveries: [:])
            }
        }
    }

    /// Returns true once the configured budget is exhausted, including on later calls.
    public func recordUsage(_ usage: TokenUsage) throws -> Bool {
        try lock.withLock { state in
            guard var current = state else { return false }
            let units: Double
            if let reported = usage.codexRolloutBudgetUnits {
                let value = reported.doubleValue ?? .nan
                guard value.isFinite, value >= 0 else {
                    throw CodexErr.fatal(
                        "response.completed usage.codex_rollout_budget_units must be finite and non-negative"
                    )
                }
                units = value
            } else {
                units = Double(max(usage.outputTokens, 0)) * current.config.samplingTokenWeight
                    + Double(usage.nonCachedInput()) * current.config.prefillTokenWeight
            }
            current.weightedTokensUsed += units
            state = current
            return current.weightedTokensUsed >= Double(current.config.limitTokens)
        }
    }

    public func pendingReminder(threadId: ThreadId, windowId: String) -> RolloutBudgetReminder? {
        lock.withLock { state in
            guard let current = state else { return nil }
            let remainingTokens = Int64(
                (Double(current.config.limitTokens) - current.weightedTokensUsed).maximum(0).rounded(.down)
            )
            let reminderIndex = Int64(
                current.config.reminderAtRemainingTokens.filter { remainingTokens <= $0 }.count
            )
            if let delivery = current.deliveries[threadId],
               delivery.windowId == windowId,
               delivery.reminderIndex >= reminderIndex
            {
                return nil
            }
            return RolloutBudgetReminder(remainingTokens: remainingTokens, reminderIndex: reminderIndex)
        }
    }

    public func markReminderDelivered(
        threadId: ThreadId,
        windowId: String,
        reminder: RolloutBudgetReminder
    ) {
        lock.withLock { state in
            guard var current = state else { return }
            current.deliveries[threadId] = ThreadBudgetDelivery(
                windowId: windowId,
                reminderIndex: reminder.reminderIndex
            )
            state = current
        }
    }
}

private extension Double {
    func maximum(_ other: Double) -> Double { Swift.max(self, other) }
}
