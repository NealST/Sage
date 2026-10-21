//
//  ExploreAgentSpawn.swift
//  Sage
//
//  explore_subagent on the Live Execute spawn path (M4): spawn an
//  explorer-role child thread off the task's root session, wait for its
//  final status, and return the child's final assistant message as the
//  tool output. Read-only scoping comes from the explorer role allowlist
//  (child sampler assembly + child dispatch gate), not a bespoke turn loop.
//

import Foundation
import SageCore
import SageProtocol

nonisolated enum ExploreSubagentTool {
    static let name = "explore_subagent"

    static let definition = ToolDefinition(
        name: name,
        description: """
        Delegate a focused read-only filesystem investigation to a nested agent. \
        The child can list directories, read text files, and search files inside the active sandbox. \
        Use when exploration needs several tool rounds but only the final findings belong in the main thread.
        """,
        parameters: .schemaObject(
            properties: [
                "task": .stringProperty("Specific question or investigation for the child agent."),
                "context": .stringProperty("Optional concise context the child needs."),
            ],
            required: ["task"]
        ),
        requiresConfirmation: false
    )
}

@MainActor
enum ExploreAgentSpawnRunner {
    /// Kept under `ToolOrchestrator`'s 130s explore timeout so the child is
    /// interrupted and the caller sees a timeout error before the
    /// orchestrator kills the whole tool call.
    static let waitTimeoutSeconds = 120
    static let defaultFindings = "The Explore subagent returned no findings."
    /// Mirrors codex `config::DEFAULT_AGENT_MAX_DEPTH` (one level of subagents).
    private static let maxSpawnDepth: Int32 = 1

    static func run(
        harness: TaskHarness,
        task: String,
        context: String?,
        instructions: String?,
        boundaryDescription: String,
        timeoutSeconds: Int = ExploreAgentSpawnRunner.waitTimeoutSeconds
    ) async throws -> String {
        guard !harness.isShutDown else {
            throw ToolError.operationFailed(
                "Explore subagent is unavailable: the task session has shut down."
            )
        }
        harness.prepareExploreSpawn()
        // Spawned children sample through the attached model client, or the
        // manually installed turn sampler when no client is attached.
        guard harness.session.services.modelClient != nil
            || harness.threadManager.turnSampler != nil else {
            throw ToolError.operationFailed("Explore subagent model settings are unavailable.")
        }
        let control = harness.threadManager.agentControl(sessionId: SessionId(harness.threadId))
        let caller = harness.threadId
        let parentSource = harness.threadManager.peekThread(caller)?.sessionSource ?? .cli
        let childDepth = nextThreadSpawnDepth(parentSource)
        if exceedsThreadSpawnDepthLimit(depth: childDepth, maxDepth: maxSpawnDepth) {
            throw ToolError.operationFailed("Agent depth limit reached. Solve the task yourself.")
        }
        let inputItems: [UserInput] = [
            .text(
                text: composeChildInput(
                    task: task,
                    context: context,
                    instructions: instructions,
                    boundaryDescription: boundaryDescription
                ),
                textElements: []
            )
        ]
        let prompt = renderInputPreview(inputItems)
        let itemID = "explore-\(UUID().uuidString)"
        let source = try threadSpawnSource(
            parentThreadId: caller,
            parentSessionSource: parentSource,
            depth: childDepth,
            agentRole: explorerRoleName,
            taskName: nil
        )
        try? await control.emitTurnItemStarted(
            threadId: caller,
            turnId: "",
            item: .collabAgentToolCall(
                CollabAgentToolCallItem(
                    id: itemID,
                    tool: .spawnAgent,
                    status: .inProgress,
                    senderThreadId: caller,
                    prompt: prompt
                )
            )
        )
        let spawned: (LiveAgent, ThreadConfigSnapshot)
        do {
            spawned = try await control.spawn(
                SpawnRequest(
                    caller: caller,
                    input: .userInput(inputItems),
                    source: source,
                    options: SpawnAgentOptions(parentThreadId: caller)
                )
            )
        } catch {
            try? await control.emitTurnItemCompleted(
                threadId: caller,
                turnId: "",
                item: .collabAgentToolCall(
                    CollabAgentToolCallItem(
                        id: itemID,
                        tool: .spawnAgent,
                        status: .failed,
                        senderThreadId: caller,
                        prompt: prompt
                    )
                )
            )
            throw error
        }
        let child = spawned.0.threadId
        let receiverAgents = [
            CollabAgentRef(
                threadId: child,
                agentNickname: spawned.1.sessionSource.getNickname() ?? spawned.0.metadata.agentNickname,
                agentRole: spawned.1.sessionSource.getAgentRole() ?? spawned.0.metadata.agentRole
            )
        ]
        let statuses = try await control.waitForFinalStatuses(
            threadIds: [child],
            timeout: .milliseconds(Int64(timeoutSeconds) * 1000)
        )
        var timedOut = false
        let finalStatus: AgentStatus
        if let entry = statuses.first(where: { $0.0 == child }) {
            finalStatus = entry.1
        } else {
            timedOut = true
            try? await control.interruptAgent(child)
            finalStatus = await control.getStatus(child)
        }
        try? await control.emitTurnItemCompleted(
            threadId: caller,
            turnId: "",
            item: .collabAgentToolCall(
                CollabAgentToolCallItem(
                    id: itemID,
                    tool: .spawnAgent,
                    status: collabToolCallStatus(finalStatus, receiverThreadId: child),
                    senderThreadId: caller,
                    receiverThreadIds: [child],
                    receiverAgents: receiverAgents,
                    prompt: prompt,
                    model: spawned.1.model,
                    agentsStates: [child: finalStatus]
                )
            )
        )
        if Task.isCancelled {
            throw CancellationError()
        }
        switch finalStatus {
        case .completed(let text):
            let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed?.nilIfEmpty ?? defaultFindings
        case .errored(let message):
            throw ToolError.operationFailed("Explore subagent failed: \(message)")
        case .interrupted where timedOut:
            throw ToolError.operationFailed(
                "Explore subagent timed out after \(timeoutSeconds) seconds."
            )
        case .interrupted:
            throw CancellationError()
        case .shutdown:
            return defaultFindings
        case .notFound:
            throw ToolError.operationFailed("Explore subagent is no longer available.")
        case .running, .pendingInit:
            throw ToolError.operationFailed(
                "Explore subagent timed out after \(timeoutSeconds) seconds."
            )
        }
    }

    /// The child sampler has no system-instruction channel, so the legacy
    /// system framing rides the initial user input verbatim.
    private static func composeChildInput(
        task: String,
        context: String?,
        instructions: String?,
        boundaryDescription: String
    ) -> String {
        var lines = [
            "You are Sage's read-only Explore subagent.",
            "Investigate the assigned question with the available filesystem tools.",
            "Stay inside this sandbox: \(boundaryDescription)",
            "Do not propose or perform mutations. Return concise findings with relevant paths and evidence.",
        ]
        if let instructions = nonEmptyOrNil(instructions) {
            lines.append(instructions)
        }
        var input = lines.joined(separator: "\n")
        input += "\n\nTask:\n\(task)"
        if let context = nonEmptyOrNil(context) {
            input += "\n\nContext:\n\(context)"
        }
        return input
    }
}
