//
//  token_budget.swift
//  Sage
//
//  Port of codex-rs/core/src/session/token_budget.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Inline token-budget compact plus resolve against model-owned
//  TokenBudgetConfig defaults. Session / HookRuntime stay app types.
//

import CodexCore
import CodexProtocol
import Foundation

func hasExplicitSettings(_ settings: StepSettings) -> Bool {
    settings.reasoningEffort != nil || settings.serviceTier != nil
}

/// Token-budget compaction skips model summarization and installs a fresh
/// window. Hooks and the `ContextCompaction` item still observe the same
/// lifecycle as local / remote compact.
func runInlineTokenBudgetCompact(
    sess: Session,
    stepContext: StepContext,
    injection: InitialContextInjection = .doNotInject,
    trigger: CompactHookTrigger = .auto
) async throws {
    let projectRoot = URL(fileURLWithPath: stepContext.turn.cwd, isDirectory: true)
    let preCompact = await HookRuntime.preCompact(
        projectRoot: projectRoot,
        trigger: trigger,
        sessionId: sess.threadId.description,
        turnId: stepContext.turn.subId,
        cwd: stepContext.turn.cwd,
        model: stepContext.turn.model
    )
    if preCompact.shouldStop {
        throw CodexErr(details: .turnAborted)
    }
    recordAdditionalContexts(
        sess: sess,
        turnContext: stepContext.turn,
        contexts: preCompact.additionalContexts
    )

    let history = sess.cloneHistory()
    let compactionItem = TurnItem.contextCompaction(ContextCompactionItem())
    sess.emitTurnItemStarted(stepContext.turn, compactionItem)
    let (windowNumber, _) = sess.startNewContextWindow()
    let compacted = applyCompactedHistoryInitialContext(
        buildCompactedHistory(
            initialContext: [],
            userMessages: collectAnnotatedUserMessages(history.items),
            summaryText: compactNoSummaryAvailable
        ),
        sess: sess,
        stepContext: stepContext,
        injection: injection
    )
    sess.replaceCompactedHistory(compacted)
    sess.lastCompactCheckpoint = CompactionCheckpointMetadata(
        windowNumber: windowNumber,
        summary: compactNoSummaryAvailable
    )
    sess.lastRemoteCompact = CompactRemoteV2Result(summary: compactNoSummaryAvailable, succeeded: true)
    sess.emitTurnItemCompleted(stepContext.turn, compactionItem)
    sess.sendEvent(stepContext.turn, .contextCompacted(ContextCompactedEvent()))

    let postCompact = await HookRuntime.postCompact(
        projectRoot: projectRoot,
        trigger: trigger,
        sessionId: sess.threadId.description,
        turnId: stepContext.turn.subId,
        cwd: stepContext.turn.cwd,
        model: stepContext.turn.model
    )
    if postCompact.shouldStop {
        throw CodexErr(details: .turnAborted)
    }
    recordAdditionalContexts(
        sess: sess,
        turnContext: stepContext.turn,
        contexts: postCompact.additionalContexts
    )
}

func resolveTokenBudget(modelContextWindow: Int64?, occupancy: Double) -> Int64? {
    guard let modelContextWindow else { return nil }
    return Int64(Double(modelContextWindow) * max(0, 1 - occupancy))
}

/// Codex `resolve_token_budget`. Model defaults fill reminder / fallback
/// fields; an invalid model-owned config keeps the user setting.
func resolveTokenBudgetConfig(
    configured: TokenBudgetConfig?,
    useModelDefaults: Bool,
    modelDefaults: ModelTokenBudgetConfig?
) -> TokenBudgetConfig? {
    guard useModelDefaults, let modelDefaults else {
        return configured
    }
    let resolved = TokenBudgetConfig(
        useHistoryNotesExtension: configured?.useHistoryNotesExtension ?? false,
        reminderThresholdTokens: modelDefaults.reminderThresholdTokens,
        reminderMessageTemplate: modelDefaults.reminderMessageTemplate,
        guidanceMessage: modelDefaults.guidanceMessage,
        autoCompactFallbackPrompt: modelDefaults.autoCompactFallbackPrompt,
        autoCompactFallbackBufferTokens: modelDefaults.autoCompactFallbackBufferTokens
    )
    if case .failure = resolved.validate() {
        return configured
    }
    return resolved
}

func resolveTokenBudgetConfig(
    configured: TokenBudgetConfig?,
    useModelDefaults: Bool,
    modelInfo: ModelInfo
) -> TokenBudgetConfig? {
    resolveTokenBudgetConfig(
        configured: configured,
        useModelDefaults: useModelDefaults,
        modelDefaults: modelInfo.modelMessages?.tokenBudget
    )
}

extension Session {
    func remainingContextTokens() -> Int64? {
        state.tokenInfo()?.modelContextWindow.map { window in
            max(window - (state.tokenInfo()?.totalTokenUsage.totalTokens ?? 0), 0)
        }
    }
}
