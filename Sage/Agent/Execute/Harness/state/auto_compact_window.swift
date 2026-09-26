//
//  auto_compact_window.swift
//  Sage
//
//  Port of codex-rs/core/src/state/auto_compact_window.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//

import CodexProtocol
import Foundation

struct AutoCompactWindowIds: Equatable, Sendable {
    var firstWindowId: UUID
    var previousWindowId: UUID?
    var windowId: UUID

    init(firstWindowId: UUID, previousWindowId: UUID? = nil, windowId: UUID) {
        self.firstWindowId = firstWindowId
        self.previousWindowId = previousWindowId
        self.windowId = windowId
    }

    static func newInitial() -> AutoCompactWindowIds {
        let windowId = UUID()
        return AutoCompactWindowIds(firstWindowId: windowId, windowId: windowId)
    }
}

struct AutoCompactWindowSnapshot: Equatable, Sendable {
    var prefillInputTokens: Int64?

    init(prefillInputTokens: Int64? = nil) {
        self.prefillInputTokens = prefillInputTokens
    }
}

enum AutoCompactWindowPrefill: Equatable, Sendable {
    case serverObserved(Int64)
    case estimated(Int64)
}

struct AutoCompactWindow: Equatable, Sendable {
    var windowNumber: UInt64
    var ids: AutoCompactWindowIds
    var newContextWindowRequested: Bool
    var prefillInputTokens: AutoCompactWindowPrefill?
    var tokenBudgetReminderDelivered: Bool
    var autoCompactFallbackDelivered: Bool

    static func newWithIds(_ ids: AutoCompactWindowIds) -> AutoCompactWindow {
        AutoCompactWindow(
            windowNumber: 0,
            ids: ids,
            newContextWindowRequested: false,
            prefillInputTokens: nil,
            tokenBudgetReminderDelivered: false,
            autoCompactFallbackDelivered: false
        )
    }

    mutating func clearPrefill() {
        prefillInputTokens = nil
    }

    mutating func restore(windowNumber: UInt64, ids: AutoCompactWindowIds) {
        self.windowNumber = windowNumber
        self.ids = ids
    }

    mutating func advance() -> (UInt64, AutoCompactWindowIds) {
        windowNumber = windowNumber &+ 1
        ids.previousWindowId = ids.windowId
        ids.windowId = UUID()
        newContextWindowRequested = false
        tokenBudgetReminderDelivered = false
        autoCompactFallbackDelivered = false
        return (windowNumber, ids)
    }

    mutating func claimTokenBudgetReminder() -> Bool {
        let previous = tokenBudgetReminderDelivered
        tokenBudgetReminderDelivered = true
        return !previous
    }

    mutating func claimAutoCompactFallback() -> Bool {
        let previous = autoCompactFallbackDelivered
        autoCompactFallbackDelivered = true
        return !previous
    }

    mutating func requestNewContextWindow() {
        newContextWindowRequested = true
    }

    mutating func takeNewContextWindowRequest() -> Bool {
        let requested = newContextWindowRequested
        newContextWindowRequested = false
        return requested
    }

    mutating func ensureServerObservedPrefillFromUsage(_ usage: CodexProtocol.TokenUsage) {
        if case .serverObserved = prefillInputTokens { return }
        prefillInputTokens = .serverObserved(max(usage.inputTokens, 0))
    }

    mutating func setEstimatedPrefill(_ tokens: Int64) {
        if case .serverObserved = prefillInputTokens { return }
        prefillInputTokens = .estimated(max(tokens, 0))
    }

    func snapshot() -> AutoCompactWindowSnapshot {
        switch prefillInputTokens {
        case .serverObserved(let tokens), .estimated(let tokens):
            return AutoCompactWindowSnapshot(prefillInputTokens: tokens)
        case nil:
            return AutoCompactWindowSnapshot()
        }
    }
}
