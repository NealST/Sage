//
//  lib.swift
//  CodexHistory
//
//  Port of codex-rs/history/src/lib.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Model-history and persisted-rollout domain types. `schemars` is omitted.
//  Retained-context / guardian-history / sender-user-messages stay as
//  optional JSON payloads until those files are ported.
//

import CodexProtocol
import Foundation

public struct CodexHarnessMetadata: Codable, Equatable, Sendable {
    public var clientAuthored: Bool
    public var historyTruncationTokenLimit: UInt64?
    public var deliveredAssistantMessage: String?
    public var harnessAuthoredConfiguration: Bool
    public var compactionModelHash: String?
    public var userInputOrder: UInt64?
    public var compactionOutput: Bool
    public var inheritedUserMessage: Bool
    public var mcpAttribution: McpAttribution?
    public var senderUserMessages: JSONValue?

    enum CodingKeys: String, CodingKey {
        case clientAuthored = "client_authored"
        case historyTruncationTokenLimit = "fallback_token_limit_override"
        case deliveredAssistantMessage = "delivered_assistant_message"
        case harnessAuthoredConfiguration = "harness_authored_configuration"
        case compactionModelHash = "compaction_model_hash"
        case userInputOrder = "user_input_order"
        case compactionOutput = "compaction_output"
        case inheritedUserMessage = "inherited_user_message"
        case mcpAttribution = "mcp_attribution"
        case senderUserMessages = "sender_user_messages"
    }

    public init() {
        clientAuthored = false
        harnessAuthoredConfiguration = false
        compactionOutput = false
        inheritedUserMessage = false
    }
}

public struct ResponseItemEnvelope: Codable, Equatable, Sendable {
    public var item: ResponseItem
    public var metadata: CodexHarnessMetadata?

    public init(item: ResponseItem, metadata: CodexHarnessMetadata? = nil) {
        self.item = item
        self.metadata = metadata
    }
}

public struct CompactedItem: Codable, Equatable, Sendable {
    public var message: String
    public var replacementHistory: [ResponseItemEnvelope]?
    public var guardianHistory: JSONValue?
    public var retainedContext: JSONValue?
    public var mcpResourceOrigins: JSONValue?
    public var windowNumber: UInt64?
    public var firstWindowId: String?
    public var previousWindowId: String?
    public var windowId: String?
    public var compactionResponseId: String?
    public var latestTokenUsageRecord: TokenUsageRecord?
    public var resumeMetadata: JSONValue?

    enum CodingKeys: String, CodingKey {
        case message
        case replacementHistory = "replacement_history"
        case guardianHistory = "guardian_history"
        case retainedContext = "retained_context"
        case mcpResourceOrigins = "mcp_resource_origins"
        case windowNumber = "window_number"
        case firstWindowId = "first_window_id"
        case previousWindowId = "previous_window_id"
        case windowId = "window_id"
        case compactionResponseId = "compaction_response_id"
        case latestTokenUsageRecord = "latest_token_usage_record"
        case resumeMetadata = "resume_metadata"
    }

    public init(message: String) {
        self.message = message
    }
}

public enum RolloutItem: Equatable, Sendable {
    case sessionMeta(SessionMetaLine)
    case responseItem(ResponseItemEnvelope)
    case interAgentCommunication(InterAgentCommunication)
    case interAgentCommunicationMetadata(triggerTurn: Bool)
    case compacted(CompactedItem)
    case turnContext(TurnContextItem)
    case tokenUsageRecord(TokenUsageRecord)
    case worldState(WorldStateItem)
    case securityRiskScore(SecurityRiskScore)
    case retainedContext(JSONValue)
    case eventMsg(EventMsg)
    case realtimeItem(RealtimeItem)
}

extension RolloutItem: Codable {
    private enum TypeKey: String, CodingKey { case type, payload, metadata }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: TypeKey.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "session_meta":
            self = .sessionMeta(try container.decode(SessionMetaLine.self, forKey: .payload))
        case "response_item":
            let item = try container.decode(ResponseItem.self, forKey: .payload)
            let metadata = try container.decodeIfPresent(CodexHarnessMetadata.self, forKey: .metadata)
            self = .responseItem(ResponseItemEnvelope(item: item, metadata: metadata))
        case "inter_agent_communication":
            self = .interAgentCommunication(try container.decode(InterAgentCommunication.self, forKey: .payload))
        case "inter_agent_communication_metadata":
            struct Payload: Decodable { var triggerTurn: Bool
                enum CodingKeys: String, CodingKey { case triggerTurn = "trigger_turn" }
            }
            self = .interAgentCommunicationMetadata(
                triggerTurn: try container.decode(Payload.self, forKey: .payload).triggerTurn)
        case "compacted":
            self = .compacted(try container.decode(CompactedItem.self, forKey: .payload))
        case "turn_context":
            self = .turnContext(try container.decode(TurnContextItem.self, forKey: .payload))
        case "token_usage_record":
            self = .tokenUsageRecord(try container.decode(TokenUsageRecord.self, forKey: .payload))
        case "world_state":
            self = .worldState(try container.decode(WorldStateItem.self, forKey: .payload))
        case "security_risk_score":
            self = .securityRiskScore(try container.decode(SecurityRiskScore.self, forKey: .payload))
        case "retained_context":
            self = .retainedContext(try container.decode(JSONValue.self, forKey: .payload))
        case "event_msg":
            self = .eventMsg(try container.decode(EventMsg.self, forKey: .payload))
        case "realtime_item":
            self = .realtimeItem(try container.decode(RealtimeItem.self, forKey: .payload))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: container, debugDescription: "Unknown RolloutItem type: \(type)")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: TypeKey.self)
        switch self {
        case .sessionMeta(let payload):
            try container.encode("session_meta", forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .responseItem(let envelope):
            try container.encode("response_item", forKey: .type)
            try container.encode(envelope.item, forKey: .payload)
            try container.encodeIfPresent(envelope.metadata, forKey: .metadata)
        case .interAgentCommunication(let payload):
            try container.encode("inter_agent_communication", forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .interAgentCommunicationMetadata(let triggerTurn):
            try container.encode("inter_agent_communication_metadata", forKey: .type)
            try container.encode(["trigger_turn": triggerTurn], forKey: .payload)
        case .compacted(let payload):
            try container.encode("compacted", forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .turnContext(let payload):
            try container.encode("turn_context", forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .tokenUsageRecord(let payload):
            try container.encode("token_usage_record", forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .worldState(let payload):
            try container.encode("world_state", forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .securityRiskScore(let payload):
            try container.encode("security_risk_score", forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .retainedContext(let payload):
            try container.encode("retained_context", forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .eventMsg(let payload):
            try container.encode("event_msg", forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .realtimeItem(let payload):
            try container.encode("realtime_item", forKey: .type)
            try container.encode(payload, forKey: .payload)
        }
    }
}

/// One persisted rollout JSONL record.
public struct RolloutLine: Equatable, Sendable {
    public var timestamp: String
    public var ordinal: UInt64?
    public var item: RolloutItem

    public init(timestamp: String, ordinal: UInt64? = nil, item: RolloutItem) {
        self.timestamp = timestamp
        self.ordinal = ordinal
        self.item = item
    }
}

public struct ResumedHistory: Equatable, Sendable {
    public var conversationId: ThreadId
    public var history: [RolloutItem]
    public var rolloutPath: String?

    public init(conversationId: ThreadId, history: [RolloutItem], rolloutPath: String? = nil) {
        self.conversationId = conversationId
        self.history = history
        self.rolloutPath = rolloutPath
    }
}

public enum InitialHistory: Equatable, Sendable {
    case new
    case cleared
    case resumed(ResumedHistory)
    case forked([RolloutItem])

    public func scanRolloutItems(_ predicate: (RolloutItem) -> Bool) -> Bool {
        switch self {
        case .new, .cleared: return false
        case .resumed(let resumed): return resumed.history.contains(where: predicate)
        case .forked(let items): return items.contains(where: predicate)
        }
    }

    public func forkedFromId() -> ThreadId? {
        switch self {
        case .new, .cleared: return nil
        case .resumed(let resumed):
            return resumed.history.compactMap {
                if case .sessionMeta(let line) = $0 { return line.meta.forkedFromId }
                return nil
            }.first
        case .forked(let items):
            return items.compactMap {
                if case .sessionMeta(let line) = $0 { return line.meta.id }
                return nil
            }.first
        }
    }

    public func getRolloutItems() -> [RolloutItem] {
        switch self {
        case .new, .cleared: return []
        case .resumed(let resumed): return resumed.history
        case .forked(let items): return items
        }
    }
}
