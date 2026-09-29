//
//  completion.swift
//  CodexCore
//
//  Port of codex-rs/core/src/agent/control/completion.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Parent-path routing and completion-message formatting are faithful.
//  Completion messages enqueue on the parent mailbox. Live activity
//  emit still waits on ThreadManager.
//

import CodexProtocol
import Foundation

extension LocalAgentControl {
    public func notifyParentOfTerminalTurn(_ outcome: AgentTurnOutcome) async {
        guard case .subAgent(
            .threadSpawn(let parentThreadId, _, let childAgentPath?, _, _)
        ) = outcome.source else {
            return
        }
        guard let parentAgentPath = parentPath(of: childAgentPath) else { return }

        if case .completed = outcome.status, let parentTurnId = outcome.parentTurnId {
            _ = parentTurnId
        }

        guard let message = formatInterAgentCompletionMessage(
            taskName: parentAgentPath,
            sender: childAgentPath,
            status: outcome.status
        ) else {
            return
        }
        _ = runtime.delivery.enqueue(
            threadId: parentThreadId,
            input: .message(message: .plaintext(message), mode: .queueOnly)
        )
    }

    public func sendInterAgentCommunication() async throws {
        throw CodexErr.unsupportedOperation(
            "send_inter_agent_communication waits on ThreadManager"
        )
    }

    public func emitSubAgentActivity() async throws {
        throw CodexErr.unsupportedOperation("emit_sub_agent_activity waits on ThreadManager")
    }
}

public func parentPath(of child: AgentPath) -> AgentPath? {
    guard let slash = child.asStr.lastIndex(of: "/") else { return nil }
    let parent = String(child.asStr[..<slash])
    return try? AgentPath(string: parent)
}
