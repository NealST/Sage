//
//  spawn_agent_v2.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/handlers/multi_agents_v2/spawn.rs
//  (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Spec, argument parsing, registry spawn, and fork_turns history copy
//  are live. emit_sub_agent_activity records on the caller CodexThread
//  when a ThreadManager is attached. Child thread create submits the
//  initial user input through ThreadSession. Analytics and
//  hide_spawn_agent_metadata stay deferred.
//

import CodexCore
import CodexProtocol

struct SpawnAgentV2Args: Decodable, Equatable, Sendable {
    var message: String
    var taskName: String
    var agentType: String?
    var model: String?
    var reasoningEffort: ReasoningEffort?
    var forkTurns: String?
    var forkContext: Bool?

    enum CodingKeys: String, CodingKey {
        case message, model
        case taskName = "task_name"
        case agentType = "agent_type"
        case reasoningEffort = "reasoning_effort"
        case forkTurns = "fork_turns"
        case forkContext = "fork_context"
    }

    func forkMode() throws -> SpawnAgentForkMode? {
        if forkContext != nil {
            throw FunctionCallError.respondToModel(
                "fork_context is not supported in MultiAgentV2; use fork_turns instead"
            )
        }
        let forkTurns = self.forkTurns?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty ?? "all"
        if forkTurns.compare("none", options: .caseInsensitive) == .orderedSame {
            return nil
        }
        if forkTurns.compare("all", options: .caseInsensitive) == .orderedSame {
            return .fullHistory
        }
        guard let lastNTurns = Int(forkTurns), lastNTurns > 0 else {
            throw FunctionCallError.respondToModel(
                "fork_turns must be `none`, `all`, or a positive integer string"
            )
        }
        return .lastNTurns(lastNTurns)
    }
}

enum SpawnAgentV2Result: Encodable, Equatable, Sendable, ToolOutput {
    case withNickname(taskName: String, nickname: String?)
    case hiddenMetadata(taskName: String)

    private enum CodingKeys: String, CodingKey {
        case taskName = "task_name"
        case nickname
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .withNickname(let taskName, let nickname):
            try container.encode(taskName, forKey: .taskName)
            try container.encodeIfPresent(nickname, forKey: .nickname)
        case .hiddenMetadata(let taskName):
            try container.encode(taskName, forKey: .taskName)
        }
    }

    func logOutput() -> String { toolOutputJsonText(self, toolName: "spawn_agent") }
    func successForLogging() -> Bool { true }
    func toResponseItem(callId: String, payload: ToolPayload) -> ResponseInputItem {
        toolOutputResponseItem(
            callId: callId, payload: payload, value: self, success: true, toolName: "spawn_agent")
    }
    func codeModeResult(_ payload: ToolPayload) -> HarnessJSON {
        toolOutputCodeModeResult(self, toolName: "spawn_agent")
    }
}

struct SpawnAgentV2Handler: CoreToolRuntime {
    func toolName() -> ToolName { ToolName(plain: "spawn_agent") }
    func spec() -> ToolSpec { createSpawnAgentToolV2(SpawnAgentToolOptions()) }

    func handle(_ invocation: ToolInvocation) async throws -> any ToolOutput {
        let arguments = try functionArguments(invocation.payload)
        let args: SpawnAgentV2Args = try parseArguments(arguments)
        let forkMode = try args.forkMode()
        let message = try messageContent(args.message)
        let control = try requireLocalAgentControl(invocation)
        let caller = try requireCallerThreadId(invocation)
        let childDepth = nextThreadSpawnDepth(invocation.sessionSource)
        if exceedsThreadSpawnDepthLimit(depth: childDepth, maxDepth: invocation.agentMaxDepth) {
            throw FunctionCallError.respondToModel(
                "Agent depth limit reached. Solve the task yourself."
            )
        }
        let roleName = args.agentType?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
        let source = try threadSpawnSource(
            parentThreadId: caller,
            parentSessionSource: invocation.sessionSource,
            depth: childDepth,
            agentRole: roleName,
            taskName: args.taskName
        )
        guard let newAgentPath = source.getAgentPath() else {
            throw FunctionCallError.respondToModel(
                "spawned agent is missing a canonical task name"
            )
        }
        let spawnedAgent: LiveAgent
        let snapshot: ThreadConfigSnapshot
        do {
            (spawnedAgent, snapshot) = try await control.spawn(
                SpawnRequest(
                    caller: caller,
                    input: .message(message: .plaintext(message), mode: .triggerTurn),
                    source: source,
                    options: SpawnAgentOptions(
                        forkParentSpawnCallId: forkMode == nil ? nil : invocation.callId,
                        forkMode: forkMode,
                        parentThreadId: caller
                    )
                )
            )
        } catch let err as CodexErr {
            throw collabSpawnError(err)
        }
        try? await control.emitSubAgentActivity(
            threadId: caller,
            turnId: invocation.turnId,
            item: SubAgentActivityItem(
                id: invocation.callId,
                kind: .started,
                agentThreadId: spawnedAgent.threadId,
                agentPath: newAgentPath
            )
        )
        let taskName = snapshot.sessionSource.getAgentPath()?.asStr
            ?? spawnedAgent.metadata.agentPath?.asStr
            ?? newAgentPath.asStr
        return SpawnAgentV2Result.withNickname(
            taskName: taskName,
            nickname: snapshot.sessionSource.getNickname() ?? spawnedAgent.metadata.agentNickname
        )
    }
}
