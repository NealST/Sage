//
//  budget.swift
//  CodexCore
//
//  Port of codex-rs/core/src/agent/control/budget.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//

import CodexProtocol
import Foundation

extension LocalAgentControl {
    public func recordRolloutBudgetUsage(_ usage: TokenUsage) throws {
        if try runtime.rolloutBudget.recordUsage(usage) {
            throw CodexErr.sessionBudgetExceeded
        }
    }

    public func pendingBudgetReminder(
        threadId: ThreadId,
        windowId: String
    ) -> RolloutBudgetReminder? {
        runtime.rolloutBudget.pendingReminder(threadId: threadId, windowId: windowId)
    }

    public func markBudgetReminderDelivered(
        threadId: ThreadId,
        windowId: String,
        reminder: RolloutBudgetReminder
    ) {
        runtime.rolloutBudget.markReminderDelivered(
            threadId: threadId,
            windowId: windowId,
            reminder: reminder
        )
    }
}
