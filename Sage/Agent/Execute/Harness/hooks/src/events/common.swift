//
//  common.swift
//  CodexHooks
//
//  Port of codex-rs/hooks/src/events/common.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  Matcher helpers are NSRegularExpression. Serialization-failure helpers
//  live with dispatcher-owned handler types.
//

import CodexProtocol
import Foundation

/// Identifies a thread-spawned subagent when a normal hook runs inside it.
public struct SubagentHookContext: Equatable, Sendable {
    public var agentId: String
    public var agentType: String

    public init(agentId: String, agentType: String) {
        self.agentId = agentId
        self.agentType = agentType
    }
}

func joinTextChunks(_ chunks: [String]) -> String? {
    chunks.isEmpty ? nil : chunks.joined(separator: "\n\n")
}

func trimmedNonEmpty(_ text: String) -> String? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

func flattenAdditionalContexts(_ additionalContexts: [[AdditionalContext]]) -> [AdditionalContext] {
    additionalContexts.flatMap { $0 }
}

func hookCompletedForToolUse(_ event: HookCompletedEvent, toolUseId: String) -> HookCompletedEvent {
    var copy = event
    copy.run = hookRunForToolUse(event.run, toolUseId: toolUseId)
    return copy
}

func hookRunForToolUse(_ run: HookRunSummary, toolUseId: String) -> HookRunSummary {
    var copy = run
    copy.id = "\(run.id):\(toolUseId)"
    return copy
}

public func matcherPatternForEvent(
    _ eventName: HookEventName,
    matcher: String?
) -> String? {
    switch eventName {
    case .preToolUse, .permissionRequest, .postToolUse, .sessionStart, .sessionEnd,
         .subagentStart, .subagentStop, .preCompact, .postCompact:
        return matcher
    case .userPromptSubmit, .stop, .interrupt:
        return nil
    }
}

public func validateMatcherPattern(_ matcher: String) throws {
    if isMatchAllMatcher(matcher) || isExactMatcher(matcher) {
        return
    }
    _ = try NSRegularExpression(pattern: matcher)
}

public func matchesMatcher(_ matcher: String?, input: String?) -> Bool {
    guard let matcher else { return true }
    if isMatchAllMatcher(matcher) { return true }
    if isExactMatcher(matcher) {
        return input.map { value in matcher.split(separator: "|").contains { $0 == value } } ?? false
    }
    guard let input,
          let regex = try? NSRegularExpression(pattern: matcher) else {
        return false
    }
    let range = NSRange(input.startIndex..<input.endIndex, in: input)
    return regex.firstMatch(in: input, options: [], range: range) != nil
}

public func matcherInputs(toolName: String, matcherAliases: [String]) -> [String] {
    [toolName] + matcherAliases
}

func isMatchAllMatcher(_ matcher: String) -> Bool {
    matcher.isEmpty || matcher == "*"
}

func isExactMatcher(_ matcher: String) -> Bool {
    matcher.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "|") }
}
