//
//  agent_communication.swift
//  CodexCore
//
//  Port of codex-rs/core/src/agent_communication.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Tracing / otel emit is a no-op until Phase 10. Types and `logging_enabled`
//  stay so callers can construct contexts without a Session.
//

import CodexProtocol
import Foundation

let AGENT_COMMUNICATION_TARGET = "codex_otel.agent_communication"

public enum AgentCommunicationKind: Equatable, Sendable {
    case spawn
    case message
    case followup
    case result

    public func asStr() -> String {
        switch self {
        case .spawn: return "spawn"
        case .message: return "message"
        case .followup: return "followup"
        case .result: return "result"
        }
    }
}

public struct AgentCommunicationContext: Equatable, Sendable {
    public var kind: AgentCommunicationKind
    public var senderThreadId: ThreadId

    public init(kind: AgentCommunicationKind, senderThreadId: ThreadId) {
        self.kind = kind
        self.senderThreadId = senderThreadId
    }
}

public func loggingEnabled() -> Bool {
    false
}

public func emitAgentCommunicationSend(
    communicationId: String,
    context: AgentCommunicationContext,
    communication: InterAgentCommunication,
    receiverThreadId: ThreadId
) {
    _ = communicationId
    _ = context
    _ = communication
    _ = receiverThreadId
}

public func emitAgentCommunicationReceive(communicationId: String) {
    _ = communicationId
}
