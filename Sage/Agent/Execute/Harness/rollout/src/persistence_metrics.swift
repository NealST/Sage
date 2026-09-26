//
//  persistence_metrics.swift
//  CodexRollout
//
//  Port of codex-rs/rollout/src/persistence_metrics.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Filter + size measurement is faithful. otel export is a no-op.
//  `EventMsg.turnAborted` is not in the Swift EventMsg subset yet.
//

import CodexHistory
import CodexProtocol
import Foundation

public enum PersistenceDecision: String, Equatable, Sendable {
    case kept
    case dropped
}

public struct RolloutSizeTotals: Equatable, Sendable {
    public var items: UInt64
    public var payloadBytes: UInt64

    public init(items: UInt64 = 0, payloadBytes: UInt64 = 0) {
        self.items = items
        self.payloadBytes = payloadBytes
    }
}

public struct RolloutItemMeasurement: Equatable, Sendable {
    public var decision: PersistenceDecision
    public var rolloutItemType: String
    public var payloadBytes: UInt64?
}

public struct RolloutPersistenceBatchMeasurement: Equatable, Sendable {
    public var preFilter: RolloutSizeTotals
    public var postFilter: RolloutSizeTotals
    public var items: [RolloutItemMeasurement]

    public init(
        preFilter: RolloutSizeTotals = RolloutSizeTotals(),
        postFilter: RolloutSizeTotals = RolloutSizeTotals(),
        items: [RolloutItemMeasurement] = []
    ) {
        self.preFilter = preFilter
        self.postFilter = postFilter
        self.items = items
    }
}

/// Measures logical JSON sizes while applying the shared rollout persistence policy once.
public func measureAndFilterRolloutItems(
    _ items: [RolloutItem],
    historyMode: ThreadHistoryMode
) -> ([RolloutItem], RolloutPersistenceBatchMeasurement) {
    var persisted: [RolloutItem] = []
    var measurement = RolloutPersistenceBatchMeasurement(items: [])
    measurement.items.reserveCapacity(items.count)
    for item in items {
        let kept = isPersistedRolloutItem(item, historyMode: historyMode)
        let decision: PersistenceDecision = kept ? .kept : .dropped
        let payloadBytes = serializedLen(item)
        addToTotals(&measurement.preFilter, payloadBytes)
        if kept {
            addToTotals(&measurement.postFilter, payloadBytes)
            persisted.append(item)
        }
        measurement.items.append(RolloutItemMeasurement(
            decision: decision,
            rolloutItemType: rolloutItemTypeName(item),
            payloadBytes: payloadBytes
        ))
    }
    return (persisted, measurement)
}

public struct RolloutPersistenceTelemetry: Sendable {
    public var threadId: ThreadId
    public init(threadId: ThreadId) { self.threadId = threadId }
    public func isEnabled() -> Bool { false }
    public func recordBatch(
        items: [RolloutItem],
        measurement: RolloutPersistenceBatchMeasurement
    ) {
        _ = (items, measurement)
    }
}

private func addToTotals(_ totals: inout RolloutSizeTotals, _ payloadBytes: UInt64?) {
    totals.items += 1
    if let payloadBytes { totals.payloadBytes += payloadBytes }
}

private func serializedLen(_ item: RolloutItem) -> UInt64? {
    guard let data = try? JSONEncoder().encode(item) else { return nil }
    return UInt64(data.count)
}

private func rolloutItemTypeName(_ item: RolloutItem) -> String {
    switch item {
    case .sessionMeta: return "session_meta"
    case .responseItem(let envelope): return responseItemType(envelope)
    case .interAgentCommunication: return "inter_agent_communication"
    case .interAgentCommunicationMetadata: return "inter_agent_communication_metadata"
    case .compacted: return "compacted"
    case .turnContext: return "turn_context"
    case .tokenUsageRecord: return "token_usage_record"
    case .worldState: return "world_state"
    case .retainedContext: return "retained_context"
    case .securityRiskScore: return "security_risk_score"
    case .realtimeItem(let item):
        switch item.content {
        case .realtimeSessionStarted: return "realtime.session_started"
        case .transcriptSegment: return "realtime.transcript_segment"
        case .bemItemPromoted: return "realtime.bem_item_promoted"
        case .realtimeSessionClosed: return "realtime.session_closed"
        }
    case .eventMsg(.itemCompleted(let event)):
        return "event.item_completed.\(turnItemType(event.item))"
    case .eventMsg: return "event.other"
    }
}

private func turnItemType(_ item: TurnItem) -> String {
    switch item {
    case .userMessage: return "user_message"
    case .functionCallOutput: return "function_call_output"
    case .hookPrompt: return "hook_prompt"
    case .agentMessage: return "agent_message"
    case .plan: return "plan"
    case .reasoning: return "reasoning"
    case .commandExecution: return "command_execution"
    case .dynamicToolCall: return "dynamic_tool_call"
    case .collabAgentToolCall: return "collab_agent_tool_call"
    case .subAgentActivity: return "sub_agent_activity"
    case .webSearch: return "web_search"
    case .imageView: return "image_view"
    case .extension: return "extension"
    case .imageGeneration: return "image_generation"
    case .enteredReviewMode: return "entered_review_mode"
    case .exitedReviewMode: return "exited_review_mode"
    case .fileChange: return "file_change"
    case .mcpToolCall: return "mcp_tool_call"
    case .contextCompaction: return "context_compaction"
    }
}

private func responseItemType(_ envelope: ResponseItemEnvelope) -> String {
    switch envelope.item {
    case .message: return "response.message"
    case .additionalTools: return "response.additional_tools"
    case .agentMessage: return "response.agent_message"
    case .reasoning: return "response.reasoning"
    case .localShellCall: return "response.local_shell_call"
    case .functionCall: return "response.function_call"
    case .toolSearchCall: return "response.tool_search_call"
    case .functionCallOutput: return "response.function_call_output"
    case .toolSearchOutput: return "response.tool_search_output"
    case .customToolCall: return "response.custom_tool_call"
    case .customToolCallOutput: return "response.custom_tool_call_output"
    case .webSearchCall: return "response.web_search_call"
    case .imageGenerationCall: return "response.image_generation_call"
    case .compaction: return "response.compaction"
    case .configurationUpdate: return "response.configuration_update"
    case .compactionTrigger: return "response.compaction_trigger"
    case .contextCompaction: return "response.context_compaction"
    case .other: return "response.other"
    }
}
