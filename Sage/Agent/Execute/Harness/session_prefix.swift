//
//  session_prefix.swift
//  CodexCore
//
//  Port of codex-rs/core/src/session_prefix.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  `InterAgentCompletionMessage` in Swift takes `sender`/`summary` and
//  renders through `ContextualUserFragment`.
//

import CodexProtocol
import CodexUtils
import Foundation

let completionMessageMaxTokens = 1_000
let completionMessageEnvelopeTokenReserve = 100
let errorMaxTokens = completionMessageMaxTokens - completionMessageEnvelopeTokenReserve
let errorNextAction =
    "This agent's turn failed. If you still need this agent, use the available collaboration tools to give it another task."

/// Helpers for model-visible session state markers that are stored in user-role
/// messages but are not user intent.
public func formatInterAgentCompletionMessage(
    taskName: AgentPath,
    sender: AgentPath,
    status: AgentStatus
) -> String? {
    let payload: String
    switch status {
    case .completed(let message):
        payload = message ?? ""
    case .errored(let error):
        let truncated = truncateTextByTokens(error, tokenBudget: Int(errorMaxTokens))
        payload = "Agent errored: \(truncated)\n\n\(errorNextAction)"
    case .shutdown:
        payload = "Agent shut down."
    case .notFound:
        payload = "Agent was not found."
    case .pendingInit, .running, .interrupted:
        return nil
    }
    return InterAgentCompletionMessage(sender: sender.description, summary: payload).renderedText()
}

public func formatSubagentContextLine(
    agentReference: String,
    agentNickname: String?
) -> String {
    if let agentNickname, !agentNickname.isEmpty {
        return "- \(agentReference): \(agentNickname)"
    }
    return "- \(agentReference)"
}
