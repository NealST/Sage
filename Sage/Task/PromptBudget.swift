//
//  PromptBudget.swift
//  Sage
//
//  Token-window budget for model-facing prompt assembly.
//

import Foundation

/// Usable token budget for one completion request.
///
/// `usableTokens` is the context window minus output slack and tool-definition
/// overhead. Prompt regions share that remainder — they do not use the raw window.
nonisolated struct PromptBudget: Sendable, Equatable {
    /// Model context window in tokens.
    var windowTokens: Int
    /// Held back for the model's reply (~10% of the window).
    var reservedOutputTokens: Int
    /// Tool definitions sent alongside messages.
    var reservedToolTokens: Int

    /// Tokens left for system text + transcript after reserves.
    var usableTokens: Int {
        max(windowTokens - reservedOutputTokens - reservedToolTokens, 1)
    }

    /// Hard cap for a single tool result: half the window.
    var maxToolResultTokens: Int {
        max(windowTokens / 2, 1)
    }

    /// UTF-8 byte ceiling matching `maxToolResultTokens` under the 4-bytes-per-token estimate.
    var maxToolResultUTF8Bytes: Int {
        maxToolResultTokens * PromptBudget.bytesPerToken
    }

    /// Creates a budget for `model`, reserving ~10% of the window for output.
    static func forModel(_ model: String) -> PromptBudget {
        let window = windowTokens(forModel: model)
        return PromptBudget(
            windowTokens: window,
            reservedOutputTokens: max(window / 10, 256),
            reservedToolTokens: 0
        )
    }

    /// Tight default used by tests and `select(from:)` when no model is in play.
    static let `default` = PromptBudget(
        windowTokens: 32_000,
        reservedOutputTokens: 3_200,
        reservedToolTokens: 0
    )

    /// Returns a copy that also reserves space for tool schemas.
    func deductingToolDefinitions(_ tools: [ToolDefinition]) -> PromptBudget {
        var copy = self
        copy.reservedToolTokens += tools.reduce(0) { $0 + Self.estimatedTokenCount(of: $1) }
        return copy
    }

    /// Rough token count: UTF-8 bytes / 4, rounded up. Empty text is 0.
    static func estimatedTokenCount(in text: String) -> Int {
        estimatedTokenCount(utf8ByteCount: text.utf8.count)
    }

    /// Rough token count for a transcript event (body + tool-call payloads).
    static func estimatedTokenCount(of event: AgentEvent) -> Int {
        estimatedTokenCount(utf8ByteCount: utf8ByteCount(of: event))
    }

    /// Rough token count for one tool schema.
    static func estimatedTokenCount(of tool: ToolDefinition) -> Int {
        var bytes = tool.name.utf8.count + tool.description.utf8.count
        if let data = try? JSONEncoder().encode(tool.parameters) {
            bytes += data.count
        }
        return estimatedTokenCount(utf8ByteCount: bytes)
    }

    static func utf8ByteCount(of event: AgentEvent) -> Int {
        let body = event.kind == .toolResult
            ? WriteFileResultCodec.modelFacing(event.content)
            : event.content
        var cost = body.utf8.count
        if let calls = event.toolCalls {
            cost += calls.reduce(0) {
                $0 + $1.argumentsJSON.utf8.count + $1.name.utf8.count
            }
        }
        return cost
    }

    static func estimatedTokenCount(utf8ByteCount: Int) -> Int {
        guard utf8ByteCount > 0 else { return 0 }
        return (utf8ByteCount + bytesPerToken - 1) / bytesPerToken
    }

    /// Inferred context window. Unknown names default to 128k.
    static func windowTokens(forModel name: String) -> Int {
        let model = name.lowercased()
        if model.contains("gpt-4.1") || model.contains("gpt-5") { return 1_000_000 }
        if model.contains("gemini") { return 1_000_000 }
        if model.contains("claude") { return 200_000 }
        if model.contains("o1") || model.contains("o3") || model.contains("o4") {
            return 200_000
        }
        return 128_000
    }

    static let bytesPerToken = 4
}
