//
//  token_budget_context.swift
//  CodexCore
//
//  Port of codex-rs/core/src/context/token_budget_context.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  World-state section protocol is inlined as renderable fragments. AgentPath
//  is represented as a string until the protocol type is ported.
//

import CodexProtocol
import Foundation

public let contextWindowOpenTag = "<context_window>"
public let contextWindowCloseTag = "</context_window>"
public let contextWindowGuidanceOpenTag = "<context_window_guidance>"
public let contextWindowGuidanceCloseTag = "</context_window_guidance>"

public struct TokenBudgetContext: ContextualUserFragment, Equatable, Sendable {
    public var agentPath: String
    public var firstWindowId: UUID
    public var previousWindowId: UUID?
    public var windowId: UUID
    public var threadHint: String?

    public init(
        agentPath: String,
        firstWindowId: UUID,
        previousWindowId: UUID? = nil,
        windowId: UUID,
        threadHint: String? = nil
    ) {
        self.agentPath = agentPath
        self.firstWindowId = firstWindowId
        self.previousWindowId = previousWindowId
        self.windowId = windowId
        self.threadHint = threadHint
    }

    public var contentKind: ContentItemKind { ContentItemKind("token_budget.context_window") }
    public var role: String { "developer" }
    public var requiresSeparateMessage: Bool { true }
    public var openMarker: String { contextWindowOpenTag }
    public var closeMarker: String { contextWindowCloseTag }

    public var body: String {
        var lines = [
            "Agent name: \(agentPath)",
            "First context window id: \(firstWindowId.uuidString.lowercased())",
            "Current context window id: \(windowId.uuidString.lowercased())",
        ]
        if let previousWindowId {
            lines.append("Previous context window id: \(previousWindowId.uuidString.lowercased())")
        }
        if let threadHint {
            lines.append(threadHint)
        }
        return "\n\(lines.joined(separator: "\n"))\n"
    }
}

public struct TokenBudgetRemainingContext: ContextualUserFragment, Equatable, Sendable {
    public var remainingTokens: Int64

    public init(remainingTokens: Int64) {
        self.remainingTokens = remainingTokens
    }

    public var contentKind: ContentItemKind { ContentItemKind("token_budget.remaining") }
    public var role: String { "developer" }
    public var openMarker: String { "<token_budget_remaining>" }
    public var closeMarker: String { "</token_budget_remaining>" }
    public var body: String {
        "You have approximately \(remainingTokens) tokens remaining in the current context window."
    }
}

public struct TokenBudgetReminder: ContextualUserFragment, Equatable, Sendable {
    public init() {}

    public var contentKind: ContentItemKind { ContentItemKind("token_budget.reminder") }
    public var role: String { "developer" }
    public var openMarker: String { "<token_budget_reminder>" }
    public var closeMarker: String { "</token_budget_reminder>" }
    public var body: String {
        "Context is filling. Prefer compacting or finishing the current task before adding more tool output."
    }
}

public struct AutoCompactFallbackPrompt: ContextualUserFragment, Equatable, Sendable {
    public init() {}

    public var contentKind: ContentItemKind { ContentItemKind("token_budget.auto_compact_fallback") }
    public var role: String { "developer" }
    public var openMarker: String { "<auto_compact_fallback>" }
    public var closeMarker: String { "</auto_compact_fallback>" }
    public var body: String {
        "Automatic compaction could not free enough space. Continue with the current window and drop older tool output if needed."
    }
}

public struct ContextWindowGuidance: ContextualUserFragment, Equatable, Sendable {
    public var text: String

    public init(text: String) {
        self.text = text
    }

    public var contentKind: ContentItemKind { ContentItemKind("token_budget.context_window_guidance") }
    public var role: String { "developer" }
    public var openMarker: String { contextWindowGuidanceOpenTag }
    public var closeMarker: String { contextWindowGuidanceCloseTag }
    public var body: String { text }
}
