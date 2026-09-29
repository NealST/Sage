//
//  agent_response.swift
//  CodexOtel
//
//  Port of codex-rs/otel/src/agent_response.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Dedup + byte bound are faithful. tracing emit is os.Logger.
//

import CodexProtocol
import CodexUtils
import Foundation
import os

private let maxResponseBytes = 65_536

/// Host-owned attribution for one live completed response item.
public struct AgentResponseContext: Sendable {
    public var turnId: String
    public var sessionSource: SessionSource
    public var parentTurnId: String?
    public var rootTurnId: String?
    public var initiatingAgentPath: AgentPath?

    public init(
        turnId: String,
        sessionSource: SessionSource,
        parentTurnId: String? = nil,
        rootTurnId: String? = nil,
        initiatingAgentPath: AgentPath? = nil
    ) {
        self.turnId = turnId
        self.sessionSource = sessionSource
        self.parentTurnId = parentTurnId
        self.rootTurnId = rootTurnId
        self.initiatingAgentPath = initiatingAgentPath
    }
}

/// One turn's response-log state. Create a fresh instance for each turn.
public final class AgentResponseLogger: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: Set<ResponseItemId>())

    public init() {}

    public func record(
        telemetry: SessionTelemetry,
        item: ResponseItem,
        context: AgentResponseContext
    ) {
        guard case .message(let id, let role, let content, let phase, _) = item,
              let itemId = id,
              phase == .finalAnswer,
              role == "assistant"
        else {
            return
        }
        let agentType: String
        let parentConversationId: String?
        switch context.sessionSource {
        case .subAgent(.threadSpawn(let parentThreadId, _, _, _, _)):
            agentType = "subagent"
            parentConversationId = parentThreadId.description
        case .cli, .vsCode, .exec, .mcp, .custom, .unknown:
            agentType = "main"
            parentConversationId = nil
        case .internal, .subAgent:
            return
        }
        let text = content.compactMap { item -> String? in
            if case .outputText(let text) = item { return text }
            return nil
        }.joined()
        let (visible, _) = stripCitations(text)
        if visible.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return
        }
        let inserted = lock.withLock { logged -> Bool in
            logged.insert(itemId).inserted
        }
        guard inserted else { return }
        let response = String(takeBytesAtCharBoundary(visible, maxb: maxResponseBytes))
        var fields: [String: String] = [
            "event.name": "codex.agent_response",
            "agent.type": agentType,
            "turn.id": context.turnId,
            "item.id": String(describing: itemId),
            "response": response,
            "response_length": String(visible.utf8.count),
            "response_truncated": String(response.utf8.count < visible.utf8.count),
        ]
        if let parentConversationId {
            fields["parent.conversation.id"] = parentConversationId
        }
        if let parentTurnId = context.parentTurnId {
            fields["parent.turn.id"] = parentTurnId
        }
        if let rootTurnId = context.rootTurnId {
            fields["root.turn.id"] = rootTurnId
        }
        if let path = context.initiatingAgentPath {
            fields["initiating.agent.path"] = path.asStr
        }
        logOtelEvent(telemetry, fields)
    }
}
