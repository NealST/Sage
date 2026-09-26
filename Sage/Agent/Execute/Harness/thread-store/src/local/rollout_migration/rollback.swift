//
//  rollback.swift
//  CodexThreadStore
//
//  Port of codex-rs/thread-store/src/local/rollout_migration/rollback.rs
//  (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Boundary predicates match the frozen migration adapter. Replacement
//  history is `[ResponseItemEnvelope]` (Swift history crate) rather than
//  bare `ResponseItem`.
//

import CodexHistory
import CodexProtocol
import Foundation

public func countsAsBoundary(_ response: ResponseItem) -> Bool {
    if case .agentMessage = response { return true }
    guard case .message(_, let role, let content, _, _) = response else { return false }
    return (role == "user" && !isKnownContextualUserMessageContent(content))
        || (role == "assistant" && InterAgentCommunication.isMessageContent(content))
}

func isPreTurnContextUpdate(_ response: ResponseItem) -> Bool {
    guard case .message(_, let role, let content, _, _) = response else { return false }
    return (role == "user" && isKnownContextualUserMessageContent(content))
        || (role == "developer" && isKnownContextualDeveloperMessageContent(content))
}

public func dropLastNUserTurns(_ history: inout [ResponseItemEnvelope], numTurns: UInt32) {
    if numTurns == 0 { return }
    let userPositions = history.enumerated().compactMap { index, item in
        countsAsBoundary(item.item) ? index : nil
    }
    guard let firstTurnIndex = userPositions.first else { return }
    let count = Int(exactly: numTurns) ?? Int.max
    var cutIndex = count >= userPositions.count
        ? firstTurnIndex
        : userPositions[userPositions.count - count]
    while cutIndex > firstTurnIndex && isPreTurnContextUpdate(history[cutIndex - 1].item) {
        cutIndex -= 1
    }
    history = Array(history.prefix(cutIndex))
}

private func isKnownContextualUserMessageContent(_ content: [ContentItem]) -> Bool {
    content.contains { item in
        guard case .inputText(let text) = item else { return false }
        return isKnownContextualUserText(text)
    }
}

private func isKnownContextualDeveloperMessageContent(_ content: [ContentItem]) -> Bool {
    content.contains { item in
        guard case .inputText(let text) = item else { return false }
        let trimmed = text.drop(while: { $0.isWhitespace })
        let prefixes = [
            "<permissions instructions>",
            "<model_switch>",
            "<managed_developer_instructions>",
            "<apps_instructions>",
            "<collaboration_mode>",
            "<multi_agent_mode>",
            "<environments_instructions>",
            "<git_attribution>",
            "<plugins_instructions>",
            "<realtime_conversation>",
            "<skills_instructions>",
            "<tools>",
            "<personality_spec>",
            "<token_budget>",
            "<context_window>",
            "<context_window_guidance>",
            "<rollout_budget>",
        ]
        return prefixes.contains { prefix in
            trimmed.prefix(prefix.count).lowercased() == prefix.lowercased()
        }
    }
}

private func isKnownContextualUserText(_ text: String) -> Bool {
    let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if parseHookPromptFragment(text) != nil { return true }
    let pairs = [
        ("# AGENTS.md instructions", "</INSTRUCTIONS>"),
        ("<environment_context>", "</environment_context>"),
        ("<skill>", "</skill>"),
        ("<user_shell_command>", "</user_shell_command>"),
        ("<turn_aborted>", "</turn_aborted>"),
        ("<subagent_notification>", "</subagent_notification>"),
        ("<recommended_plugins>", "</recommended_plugins>"),
        ("<goal_context>", "</goal_context>"),
    ]
    if pairs.contains(where: { text.hasPrefix($0.0) && text.hasSuffix($0.1) }) {
        return true
    }
    if text.hasPrefix("<external_"), let close = text.firstIndex(of: ">") {
        let keyStart = text.index(text.startIndex, offsetBy: "<external_".count)
        let key = text[keyStart..<close]
        if text.hasSuffix("</external_\(key)>") { return true }
    }
    if text.hasPrefix("<codex_internal_context") && text.hasSuffix("</codex_internal_context>") {
        return true
    }
    if text.hasPrefix(
        "Warning: The maximum number of unified exec processes you can keep open is")
    {
        return true
    }
    if text.hasPrefix("Warning: apply_patch was requested via ")
        && text.hasSuffix("Use the apply_patch tool instead of exec_command.")
    {
        return true
    }
    if text.hasPrefix(
        "Warning: Your account was flagged for potentially high-risk cyber activity")
    {
        return true
    }
    return false
}
