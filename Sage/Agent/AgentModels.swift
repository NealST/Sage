//
//  AgentModels.swift
//  Sage
//

import Foundation

nonisolated enum AgentEventKind: String, Codable, Sendable {
    case systemInstruction
    case userInput
    case assistantResponse
    case toolResult
}

nonisolated struct ToolCallRecord: Codable, Sendable, Equatable {
    let id: String
    let name: String
    let argumentsJSON: String
}

/// Explains which historical tasks were selected for a user input.
/// Kept with the event so context decisions remain inspectable and debuggable.
nonisolated struct EventContext: Codable, Sendable, Equatable {
    var relatedTaskIDs: [UUID]
    var confidence: Double
    var reason: String
}

/// An immutable item in Sage's internal task history.
///
/// Events are persisted independently from model-provider wire formats so the
/// product can change providers or context strategies without migrating data.
nonisolated struct AgentEvent: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    var kind: AgentEventKind
    var content: String
    var toolCallID: String?
    var toolCalls: [ToolCallRecord]?
    var context: EventContext?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        kind: AgentEventKind,
        content: String = "",
        toolCallID: String? = nil,
        toolCalls: [ToolCallRecord]? = nil,
        context: EventContext? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.kind = kind
        self.content = content
        self.toolCallID = toolCallID
        self.toolCalls = toolCalls
        self.context = context
        self.createdAt = createdAt
    }
}

nonisolated enum StepStatus: String, Codable, Sendable {
    case pending
    case running
    case succeeded
    case failed
    case skipped
}

nonisolated struct AgentStep: Identifiable, Codable, Sendable, Equatable {
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

nonisolated struct AgentPlan: Identifiable, Codable, Sendable, Equatable {
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
