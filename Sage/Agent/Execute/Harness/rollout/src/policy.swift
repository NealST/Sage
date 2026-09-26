//
//  policy.swift
//  CodexRollout
//
//  Port of codex-rs/rollout/src/policy.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  `EventMsg` in Swift is still a subset of the Rust enum. Persist-true
//  variants that are not yet ported (TokenCount, ThreadGoalUpdated,
//  TurnAborted, ThreadSettingsApplied) fall through to `false` until
//  protocol grows those cases. `ExtensionItem` is a kind-string placeholder.
//

import CodexHistory
import CodexProtocol
import Foundation

/// Whether a rollout `item` should be persisted in rollout files.
public func isPersistedRolloutItem(_ item: RolloutItem, historyMode: ThreadHistoryMode) -> Bool {
    switch item {
    case .responseItem(let envelope):
        return shouldPersistResponseItem(envelope.item)
    case .interAgentCommunication, .interAgentCommunicationMetadata:
        return true
    case .eventMsg(let event):
        return shouldPersistEventMsg(event, historyMode: historyMode)
    case .realtimeItem:
        return historyMode == .paginated
    case .compacted, .turnContext, .tokenUsageRecord, .worldState,
         .retainedContext, .securityRiskScore, .sessionMeta:
        return true
    }
}

/// Return the rollout items that should be persisted for a live append.
public func persistedRolloutItems(_ items: [RolloutItem], historyMode: ThreadHistoryMode) -> [RolloutItem] {
    items.filter { isPersistedRolloutItem($0, historyMode: historyMode) }
}

/// Whether a `ResponseItem` should be persisted in rollout files.
public func shouldPersistResponseItem(_ item: ResponseItem) -> Bool {
    switch item {
    case .message, .agentMessage, .reasoning, .localShellCall, .functionCall,
         .toolSearchCall, .functionCallOutput, .toolSearchOutput, .customToolCall,
         .customToolCallOutput, .webSearchCall, .imageGenerationCall,
         .configurationUpdate, .compaction, .contextCompaction:
        return true
    case .additionalTools, .compactionTrigger, .other:
        return false
    }
}

/// Whether a `ResponseItem` should be persisted for the memories.
public func shouldPersistResponseItemForMemories(_ item: ResponseItem) -> Bool {
    switch item {
    case .message(_, let role, _, _, _):
        return role != "developer"
    case .agentMessage, .localShellCall, .functionCall, .toolSearchCall,
         .functionCallOutput, .toolSearchOutput, .customToolCall,
         .customToolCallOutput, .webSearchCall:
        return true
    case .additionalTools, .reasoning, .configurationUpdate, .imageGenerationCall,
         .compaction, .compactionTrigger, .contextCompaction, .other:
        return false
    }
}

/// Whether an `EventMsg` should be persisted in rollout files.
public func shouldPersistEventMsg(_ event: EventMsg, historyMode: ThreadHistoryMode) -> Bool {
    switch event {
    case .itemCompleted(let completed):
        if historyMode == .paginated { return true }
        switch completed.item {
        case .functionCallOutput, .plan:
            return true
        case .extension(let item) where item.kind.lowercased() == "sleep":
            return true
        case .subAgentActivity(let item) where item.kind == .completed:
            return true
        default:
            return false
        }
    case .turnStarted, .turnComplete, .threadRolledBack:
        return true
    case .userMessage, .agentMessage, .agentReasoning, .agentReasoningRawContent,
         .enteredReviewMode, .exitedReviewMode, .patchApplyEnd, .contextCompacted,
         .mcpToolCallEnd, .webSearchEnd, .imageGenerationEnd:
        return historyMode == .legacy
    case .subAgentActivity(let activity):
        return historyMode == .legacy && activity.kind != .completed
    default:
        return false
    }
}
