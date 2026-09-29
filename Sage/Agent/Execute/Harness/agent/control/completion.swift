//
//  completion.swift
//  CodexCore
//
//  Port of codex-rs/core/src/agent/control/completion.rs plus
//  send_inter_agent_communication / emit_sub_agent_activity from
//  codex-rs/core/src/agent/control.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Parent-path routing, mailbox delivery, live-thread submit/event
//  recording, and Session-free turn-item emit are wired. Session
//  send_event_raw / residency pin stay later.
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
            let initiatingThreadId: ThreadId?
            if let initiatingAgentPath = outcome.initiatingAgentPath,
               initiatingAgentPath != parentAgentPath
            {
                initiatingThreadId = try? runtime.resolveAgentReference(
                    currentSessionSource: outcome.source,
                    agentReference: initiatingAgentPath.asStr
                )
            } else {
                initiatingThreadId = parentThreadId
            }
            if let initiatingThreadId {
                try? await emitSubAgentActivity(
                    threadId: initiatingThreadId,
                    turnId: parentTurnId,
                    item: SubAgentActivityItem(
                        id: "subagent-completed-\(outcome.turnId)",
                        kind: .completed,
                        agentThreadId: outcome.threadId,
                        agentPath: childAgentPath
                    )
                )
            }
        }

        guard let message = formatInterAgentCompletionMessage(
            taskName: parentAgentPath,
            sender: childAgentPath,
            status: outcome.status
        ) else {
            return
        }
        let communication = InterAgentCommunication(
            author: childAgentPath,
            recipient: parentAgentPath,
            otherRecipients: [],
            content: message,
            triggerTurn: false
        )
        let context = AgentCommunicationContext(kind: .result, senderThreadId: outcome.threadId)
        _ = try? await sendInterAgentCommunication(
            agentId: parentThreadId,
            communication: communication,
            context: context,
            startOptions: TurnStartOptions()
        )
    }

    public func sendInterAgentCommunication(
        agentId: ThreadId,
        communication: InterAgentCommunication,
        context: AgentCommunicationContext,
        startOptions: TurnStartOptions
    ) async throws -> String {
        if communication.triggerTurn {
            let manager = try runtime.upgradeThreadManager()
            let thread = try await manager.getThread(agentId)
            try ensureExecutionCapacity(.v2, sessionSource: thread.sessionSource)
        }
        return try await submitInterAgentCommunication(
            agentId: agentId,
            communication: communication,
            context: context,
            startOptions: startOptions
        )
    }

    public func emitSubAgentActivity(
        threadId: ThreadId,
        turnId: String,
        item: SubAgentActivityItem
    ) async throws {
        try await emitTurnItemStarted(
            threadId: threadId,
            turnId: turnId,
            item: .subAgentActivity(item)
        )
        try await emitTurnItemCompleted(
            threadId: threadId,
            turnId: turnId,
            item: .subAgentActivity(item)
        )
    }

    public func emitTurnItemStarted(
        threadId: ThreadId,
        turnId: String,
        item: TurnItem
    ) async throws {
        let manager = try runtime.upgradeThreadManager()
        let thread = try await manager.getThread(threadId)
        thread.emitTurnItemStarted(turnId: turnId, item: item)
    }

    public func emitTurnItemCompleted(
        threadId: ThreadId,
        turnId: String,
        item: TurnItem
    ) async throws {
        let manager = try runtime.upgradeThreadManager()
        let thread = try await manager.getThread(threadId)
        thread.emitTurnItemCompleted(turnId: turnId, item: item)
    }

    func handleThreadRequestResult(
        agentId: ThreadId,
        _ body: () async throws -> String
    ) async throws -> String {
        do {
            return try await body()
        } catch let err as CodexErr {
            if case .internalAgentDied = err.detailsValue() {
                if let manager = try? runtime.upgradeThreadManager() {
                    _ = await manager.removeThread(agentId)
                }
                runtime.residency.remove(agentId)
                runtime.registry.releaseSpawnedThread(agentId)
            }
            throw err
        }
    }

    private func submitInterAgentCommunication(
        agentId: ThreadId,
        communication: InterAgentCommunication,
        context: AgentCommunicationContext,
        startOptions: TurnStartOptions
    ) async throws -> String {
        let mode: MessageDeliveryMode = communication.triggerTurn ? .triggerTurn : .queueOnly
        let input: AgentInput
        if let encrypted = communication.encryptedContent {
            input = .message(message: .encrypted(encrypted), mode: mode)
        } else {
            input = .message(message: .plaintext(communication.content), mode: mode)
        }
        let submissionId = runtime.delivery.enqueue(threadId: agentId, input: input)
        if communication.triggerTurn {
            runtime.publishAgentStatus(agentId, .running)
        }
        if let manager = try? runtime.upgradeThreadManager() {
            let parentTurnId = communication.triggerTurn ? startOptions.parentTurnId : nil
            let rootTurnId = communication.triggerTurn ? startOptions.rootTurnId : nil
            let submitted = try await handleThreadRequestResult(agentId: agentId) {
                try await manager.sendOp(
                    agentId,
                    op: .interAgentCommunication(communication, startOptions: startOptions),
                    parentTurnId: parentTurnId,
                    rootTurnId: rootTurnId
                )
            }
            emitAgentCommunicationSend(
                communicationId: submitted,
                context: context,
                communication: communication,
                receiverThreadId: agentId
            )
            return submitted
        }
        emitAgentCommunicationSend(
            communicationId: submissionId,
            context: context,
            communication: communication,
            receiverThreadId: agentId
        )
        return submissionId
    }
}

public func parentPath(of child: AgentPath) -> AgentPath? {
    guard let slash = child.asStr.lastIndex(of: "/") else { return nil }
    let parent = String(child.asStr[..<slash])
    return try? AgentPath(string: parent)
}
