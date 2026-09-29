//
//  context_window.swift
//  Sage
//
//  Port of codex-rs/core/src/session/context_window.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Token-status math is faithful. Config.token_budget fallback buffer
//  is 0 until TokenBudgetConfig lands.
//

import CodexProtocol
import Foundation

struct ContextWindowTokenStatus: Equatable, Sendable {
    var activeContextTokens: Int64
    var autoCompactScopeTokens: Int64
    var autoCompactScopeLimit: Int64?
    var fullContextWindowLimit: Int64?
    var baseWindowTokensRemaining: Int64?
    var autoCompactWindowPrefillTokens: Int64?
    var fullContextWindowLimitReached: Bool
    var tokenLimitReached: Bool
    var turnEndCompactionThresholdReached: Bool
}

func tokensRemaining(limit: Int64?, used: Int64) -> Int64? {
    limit.map { max($0 - used, 0) }
}

func contextWindowTokenStatus(
    sess: Session,
    turnContext: TurnContext
) -> ContextWindowTokenStatus {
    contextWindowTokenStatus(
        sess: sess,
        config: turnContext.config,
        turnContext: turnContext
    )
}

func contextWindowTokenStatus(
    sess: Session,
    config: Config,
    turnContext: TurnContext
) -> ContextWindowTokenStatus {
    let activeContextTokens = sess.getTotalTokenUsage()
    let window = sess.autoCompactWindowSnapshot()

    let autoCompactScopeTokens: Int64
    let autoCompactScopeLimit: Int64?
    let autoCompactWindowPrefillTokens: Int64?
    switch config.modelAutoCompactTokenLimitScope {
    case .total:
        autoCompactScopeTokens = activeContextTokens
        autoCompactScopeLimit = turnContext.autoCompactTokenLimit()
        autoCompactWindowPrefillTokens = nil
    case .bodyAfterPrefix:
        let baseline = window.prefillInputTokens ?? activeContextTokens
        autoCompactScopeTokens = max(activeContextTokens - baseline, 0)
        autoCompactScopeLimit = config.modelAutoCompactTokenLimit ?? turnContext.autoCompactTokenLimit()
        autoCompactWindowPrefillTokens = window.prefillInputTokens
    }

    let fullContextWindowLimit = turnContext.usableContextWindow()
    let baseWindowTokensRemaining = [
        tokensRemaining(limit: autoCompactScopeLimit, used: autoCompactScopeTokens),
        tokensRemaining(limit: fullContextWindowLimit, used: activeContextTokens),
    ].compactMap { $0 }.min()

    let autoCompactFallbackBufferTokens: Int64 = 0
    let bufferedAutoCompactLimit = autoCompactScopeLimit.map { $0 &+ autoCompactFallbackBufferTokens }
    let fullContextWindowLimitReached = fullContextWindowLimit.map { activeContextTokens >= $0 } ?? false
    let tokenLimitReached =
        (bufferedAutoCompactLimit.map { autoCompactScopeTokens >= $0 } ?? false)
        || fullContextWindowLimitReached
    let postTurnPercent = config.modelPostTurnCompactThresholdPercent
    let turnEndCompactionThresholdReached: Bool
    if postTurnPercent > 0, let fullLimit = fullContextWindowLimit {
        let crossedPercent =
            Int128(activeContextTokens) * 100 >= Int128(fullLimit) * Int128(postTurnPercent)
        turnEndCompactionThresholdReached = tokenLimitReached || crossedPercent
    } else {
        turnEndCompactionThresholdReached = tokenLimitReached && postTurnPercent > 0
    }

    return ContextWindowTokenStatus(
        activeContextTokens: activeContextTokens,
        autoCompactScopeTokens: autoCompactScopeTokens,
        autoCompactScopeLimit: autoCompactScopeLimit,
        fullContextWindowLimit: fullContextWindowLimit,
        baseWindowTokensRemaining: baseWindowTokensRemaining,
        autoCompactWindowPrefillTokens: autoCompactWindowPrefillTokens,
        fullContextWindowLimitReached: fullContextWindowLimitReached,
        tokenLimitReached: tokenLimitReached,
        turnEndCompactionThresholdReached: turnEndCompactionThresholdReached
    )
}

extension Session {
    func requestNewContextWindow() {
        state.requestNewContextWindow()
    }
}
