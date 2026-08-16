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
    /// When true, this event is exempt from context budget pruning (e.g., skill instructions).
    var protected: Bool
    var createdAt: Date

    init(
        id: UUID = UUID(),
        kind: AgentEventKind,
        content: String = "",
        toolCallID: String? = nil,
        toolCalls: [ToolCallRecord]? = nil,
        context: EventContext? = nil,
        protected: Bool = false,
        createdAt: Date = .now
    ) {
        self.id = id
        self.kind = kind
        self.content = content
        self.toolCallID = toolCallID
        self.toolCalls = toolCalls
        self.context = context
        self.protected = protected
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decode(AgentEventKind.self, forKey: .kind)
        content = try container.decode(String.self, forKey: .content)
        toolCallID = try container.decodeIfPresent(String.self, forKey: .toolCallID)
        toolCalls = try container.decodeIfPresent([ToolCallRecord].self, forKey: .toolCalls)
        context = try container.decodeIfPresent(EventContext.self, forKey: .context)
        protected = try container.decodeIfPresent(Bool.self, forKey: .protected) ?? false
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, content, toolCallID, toolCalls, context, protected, createdAt
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

    /// True when any step can change the user's world (files, apps, clipboard, …).
    var requiresConfirmation: Bool {
        steps.contains { ToolDefinition.requiresConfirmation(forToolNamed: $0.toolName) }
    }
}

/// Which confirm chrome to show. Work plan and tool batch must not share a card.
enum AgentTurnChrome: Equatable, Sendable {
    case workPlan
    case toolBatch

    static func resolve(
        phase: AgentPhase,
        hasWorkPlan: Bool,
        hasToolBatch: Bool
    ) -> AgentTurnChrome? {
        switch phase {
        case .executing:
            return hasToolBatch ? .toolBatch : nil
        case .awaitingConfirmation:
            if hasToolBatch { return .toolBatch }
            if hasWorkPlan { return .workPlan }
            return nil
        default:
            return nil
        }
    }
}

enum AgentPhase: Equatable {
    case idle
    case thinking
    /// Work plan lives on `TaskRecord.workPlan`. Tool batch on `PlanProgress` / `pendingPlan`.
    case awaitingConfirmation
    /// Step detail lives on `PlanProgress`.
    case executing
    case completed(summary: String)
    case failed(message: String)
}

/// State for retry countdown display — embedded in the @Observable AgentRuntime.
struct RetryDisplayState: Equatable {
    var attempt: Int
    var maxAttempts: Int
    var totalSeconds: Int
    var secondsRemaining: Int
}

/// Cumulative token usage for the current session.
nonisolated struct TokenUsage: Equatable, Sendable {
    var input: Int = 0
    var output: Int = 0
    var total: Int { input + output }
}

extension String {
    nonisolated var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
