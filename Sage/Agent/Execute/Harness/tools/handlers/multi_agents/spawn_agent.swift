//
//  spawn_agent.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/handlers/multi_agents/spawn.rs
//  (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Spec, argument parsing, registry spawn, fork_context, and
//  turn-item recording on the caller CodexThread are live. Child thread
//  create submits the initial user input through ThreadSession.
//  Analytics stay deferred. R4a: basename `spawn.swift` belongs to
//  core/src/spawn.rs.
//

import CodexCore
import CodexProtocol

struct SpawnAgentArgs: Decodable, Equatable, Sendable {
    var message: String?
    var items: [UserInput]?
    var agentType: String?
    var model: String?
    var reasoningEffort: ReasoningEffort?
    var forkContext: Bool

    enum CodingKeys: String, CodingKey {
        case message, items, model
        case agentType = "agent_type"
        case reasoningEffort = "reasoning_effort"
        case forkContext = "fork_context"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        items = try container.decodeIfPresent([UserInput].self, forKey: .items)
        agentType = try container.decodeIfPresent(String.self, forKey: .agentType)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        reasoningEffort = try container.decodeIfPresent(ReasoningEffort.self, forKey: .reasoningEffort)
        forkContext = try container.decodeIfPresent(Bool.self, forKey: .forkContext) ?? false
    }
}

struct SpawnAgentResult: Encodable, Equatable, Sendable, ToolOutput {
    var agentId: String
    var nickname: String?

    enum CodingKeys: String, CodingKey {
        case agentId = "agent_id"
        case nickname
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

struct SpawnAgentHandler: CoreToolRuntime {
    func toolName() -> ToolName { ToolName(namespaced: MULTI_AGENT_V1_NAMESPACE, name: "spawn_agent") }
    func spec() -> ToolSpec { createSpawnAgentToolV1(SpawnAgentToolOptions()) }
    func searchInfo() -> ToolSearchInfo? {
        multiAgentToolSearchInfo(
            searchText:
                "spawn_agent spawn agent subagent sub-agent delegate delegation parallel work worker explorer no-apps fork model reasoning",
            spec: spec()
        )
    }

    func handle(_ invocation: ToolInvocation) async throws -> any ToolOutput {
        let arguments = try functionArguments(invocation.payload)
        let args: SpawnAgentArgs = try parseArguments(arguments)
        let inputItems = try parseCollabInput(message: args.message, items: args.items)
        let prompt = renderInputPreview(inputItems)
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
            taskName: nil
        )
        try? await control.emitTurnItemStarted(
            threadId: caller,
            turnId: invocation.turnId,
            item: .collabAgentToolCall(
                CollabAgentToolCallItem(
                    id: invocation.callId,
                    tool: .spawnAgent,
                    status: .inProgress,
                    senderThreadId: caller,
                    prompt: prompt,
                    model: args.model ?? "",
                    reasoningEffort: args.reasoningEffort ?? .medium
                )
            )
        )
        var spawnedAgent: LiveAgent?
        var snapshot: ThreadConfigSnapshot?
        var spawnError: Error?
        do {
            let spawned = try await control.spawn(
                SpawnRequest(
                    caller: caller,
                    input: .userInput(inputItems),
                    source: source,
                    options: SpawnAgentOptions(
                        forkParentSpawnCallId: args.forkContext ? invocation.callId : nil,
                        forkMode: args.forkContext ? .fullHistory : nil,
                        parentThreadId: caller
                    )
                )
            )
            spawnedAgent = spawned.0
            snapshot = spawned.1
        } catch {
            spawnError = error
        }
        let newThreadId = spawnedAgent?.threadId
        let status = spawnedAgent?.status ?? .notFound
        let nickname = snapshot?.sessionSource.getNickname() ?? spawnedAgent?.metadata.agentNickname
        let role = snapshot?.sessionSource.getAgentRole() ?? spawnedAgent?.metadata.agentRole
        let receiverAgents = newThreadId.map {
            CollabAgentRef(threadId: $0, agentNickname: nickname, agentRole: role)
        }.map { [$0] } ?? []
        let agentsStates = newThreadId.map { [$0: status] } ?? [:]
        try? await control.emitTurnItemCompleted(
            threadId: caller,
            turnId: invocation.turnId,
            item: .collabAgentToolCall(
                CollabAgentToolCallItem(
                    id: invocation.callId,
                    tool: .spawnAgent,
                    status: collabToolCallStatus(status, receiverThreadId: newThreadId),
                    senderThreadId: caller,
                    receiverThreadIds: newThreadId.map { [$0] } ?? [],
                    receiverAgents: receiverAgents,
                    prompt: prompt,
                    model: snapshot?.model ?? args.model ?? "",
                    reasoningEffort: args.reasoningEffort ?? .medium,
                    agentsStates: agentsStates
                )
            )
        )
        if let spawnError {
            throw (spawnError as? CodexErr).map(collabSpawnError) ?? spawnError
        }
        guard let spawnedAgent else {
            throw FunctionCallError.respondToModel("collab spawn failed")
        }
        return SpawnAgentResult(
            agentId: spawnedAgent.threadId.description,
            nickname: nickname
        )
    }
}
