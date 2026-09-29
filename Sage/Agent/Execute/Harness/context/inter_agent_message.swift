//
//  inter_agent_message.swift
//  CodexCore
//
//  Port of codex-rs/core/src/context/inter_agent_message.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//

import CodexProtocol
import Foundation

public enum InterAgentMessageType: Equatable, Sendable {
    case message
    case newTask

    public func asStr() -> String {
        switch self {
        case .message: return "MESSAGE"
        case .newTask: return "NEW_TASK"
        }
    }
}

public struct InterAgentMessage: ContextualUserFragment, Equatable, Sendable {
    public var messageType: InterAgentMessageType
    public var taskName: AgentPath
    public var sender: AgentPath
    public var payload: String

    public init(
        messageType: InterAgentMessageType,
        taskName: AgentPath,
        sender: AgentPath,
        payload: String
    ) {
        self.messageType = messageType
        self.taskName = taskName
        self.sender = sender
        self.payload = payload
    }

    public var contentKind: ContentItemKind { ContentItemKind("multi_agent.inter_agent_message") }
    public var role: String { "assistant" }
    public var openMarker: String { "" }
    public var closeMarker: String { "" }
    public var body: String {
        """
        Message Type: \(messageType.asStr())
        Task name: \(taskName.asStr)
        Sender: \(sender.asStr)
        Payload:
        \(payload)
        """
    }
}
