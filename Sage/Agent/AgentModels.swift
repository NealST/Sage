//
//  AgentModels.swift
//  Sage
//

import Foundation

enum MessageRole: String, Codable, Sendable {
    case system
    case user
    case assistant
    case tool
}

struct StoredToolCall: Codable, Sendable, Equatable {
    let id: String
    let name: String
    let argumentsJSON: String
}

struct ChatMessage: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    var role: MessageRole
    var content: String
    var toolCallID: String?
    var toolCalls: [StoredToolCall]?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String = "",
        toolCallID: String? = nil,
        toolCalls: [StoredToolCall]? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.toolCallID = toolCallID
        self.toolCalls = toolCalls
        self.createdAt = createdAt
    }
}

enum StepStatus: String, Codable, Sendable {
    case pending
    case running
    case succeeded
    case failed
    case skipped
}

struct AgentStep: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    var toolCallID: String
    var toolName: String
    var argumentsJSON: String
    var title: String
    var status: StepStatus
    var result: String?

    init(
        id: UUID = UUID(),
        toolCallID: String,
        toolName: String,
        argumentsJSON: String,
        title: String,
        status: StepStatus = .pending,
        result: String? = nil
    ) {
        self.id = id
        self.toolCallID = toolCallID
        self.toolName = toolName
        self.argumentsJSON = argumentsJSON
        self.title = title
        self.status = status
        self.result = result
    }
}

struct AgentPlan: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    var summary: String
    var steps: [AgentStep]

    init(id: UUID = UUID(), summary: String, steps: [AgentStep]) {
        self.id = id
        self.summary = summary
        self.steps = steps
    }
}

enum AgentPhase: Equatable {
    case idle
    case thinking
    case awaitingConfirmation(AgentPlan)
    case executing(AgentPlan)
    case completed(summary: String)
    case failed(message: String)
}
