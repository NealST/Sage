//
//  wait_agent.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/handlers/multi_agents/wait.rs
//  (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Spec (through `WaitAgentTimeoutOptions`), argument parsing, and the
//  subscribeStatus wait are live when LocalAgentControl is attached. The
//  initial subscription loop runs per target like rust `wait_agent`:
//  already-final targets return immediately, a missing thread maps to
//  `notFound`, and a failed subscription reports that target's id.
//  Timeout validation keeps the shared constants (rust v1 does the same;
//  configured timeouts only shape the spec, which waits on Session /
//  Config wiring). Turn items record on the caller SageThread when a
//  ThreadManager is present.
//

import SageCore
import SageProtocol
import Foundation

struct WaitArgs: Decodable, Equatable, Sendable {
    var targets: [String]
    var timeoutMs: Int64?

    enum CodingKeys: String, CodingKey {
        case targets
        case timeoutMs = "timeout_ms"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        targets = try container.decodeIfPresent([String].self, forKey: .targets) ?? []
        timeoutMs = try container.decodeIfPresent(Int64.self, forKey: .timeoutMs)
    }
}

struct WaitAgentResult: Encodable, Equatable, Sendable, ToolOutput {
    var status: [String: AgentStatus]
    var timedOut: Bool

    enum CodingKeys: String, CodingKey {
        case status
        case timedOut = "timed_out"
    }

    func logOutput() -> String { toolOutputJsonText(self, toolName: "wait_agent") }
    func successForLogging() -> Bool { true }
    func toResponseItem(callId: String, payload: ToolPayload) -> ResponseInputItem {
        toolOutputResponseItem(
            callId: callId, payload: payload, value: self, success: nil, toolName: "wait_agent")
    }
    func codeModeResult(_ payload: ToolPayload) -> HarnessJSON {
        toolOutputCodeModeResult(self, toolName: "wait_agent")
    }
}

struct WaitAgentHandler: CoreToolRuntime {
    let options: WaitAgentTimeoutOptions

    init(options: WaitAgentTimeoutOptions = WaitAgentTimeoutOptions()) {
        self.options = options
    }

    func toolName() -> ToolName { ToolName(namespaced: MULTI_AGENT_V1_NAMESPACE, name: "wait_agent") }
    func spec() -> ToolSpec { createWaitAgentToolV1(options) }
    func searchInfo() -> ToolSearchInfo? {
        multiAgentToolSearchInfo(
            searchText: "wait_agent wait agent subagent status final result complete timeout targets",
            spec: spec()
        )
    }

    func handle(_ invocation: ToolInvocation) async throws -> any ToolOutput {
        let arguments = try functionArguments(invocation.payload)
        let args: WaitArgs = try parseArguments(arguments)
        let targets = try parseAgentIdTargets(args.targets)
        let timeoutMs = try clampWaitTimeoutMs(args.timeoutMs)
        let control = try requireLocalAgentControl(invocation)
        let caller = try requireCallerThreadId(invocation)

        var receiverAgents: [CollabAgentRef] = []
        var targetByThreadId: [ThreadId: String] = [:]
        receiverAgents.reserveCapacity(targets.count)
        for threadId in targets {
            let metadata = control.getAgentMetadata(threadId) ?? AgentMetadata()
            targetByThreadId[threadId] = metadata.agentPath?.asStr ?? threadId.description
            receiverAgents.append(
                CollabAgentRef(
                    threadId: threadId,
                    agentNickname: metadata.agentNickname,
                    agentRole: metadata.agentRole
                )
            )
        }

        try? await control.emitTurnItemStarted(
            threadId: caller,
            turnId: invocation.turnId,
            item: .collabAgentToolCall(
                CollabAgentToolCallItem(
                    id: invocation.callId,
                    tool: .wait,
                    status: .inProgress,
                    senderThreadId: caller,
                    receiverThreadIds: targets,
                    receiverAgents: receiverAgents
                )
            )
        )

        var initialFinalStatuses: [(ThreadId, AgentStatus)] = []
        for threadId in targets {
            do {
                let updates = try await control.subscribeStatus(agentId: threadId)
                var iterator = updates.makeAsyncIterator()
                guard let initial = await iterator.next() else {
                    throw SageErr.internalAgentDied
                }
                let status = initial.status() ?? .notFound
                if isFinal(status) {
                    initialFinalStatuses.append((threadId, status))
                }
            } catch let err as SageErr {
                if case .threadNotFound = err.detailsValue() {
                    initialFinalStatuses.append((threadId, .notFound))
                    continue
                }
                var failed: [ThreadId: AgentStatus] = [:]
                failed[threadId] = await control.getStatus(threadId)
                try? await control.emitTurnItemCompleted(
                    threadId: caller,
                    turnId: invocation.turnId,
                    item: .collabAgentToolCall(
                        CollabAgentToolCallItem(
                            id: invocation.callId,
                            tool: .wait,
                            status: waitToolCallStatus(failed),
                            senderThreadId: caller,
                            receiverThreadIds: Array(failed.keys),
                            receiverAgents: waitReceiverAgents(failed, receiverAgents: receiverAgents),
                            agentsStates: failed
                        )
                    )
                )
                throw collabAgentError(agentId: threadId, err: err)
            }
        }

        let statuses: [(ThreadId, AgentStatus)]
        if !initialFinalStatuses.isEmpty {
            statuses = initialFinalStatuses
        } else {
            statuses = try await control.raceFinalStatuses(
                threadIds: targets,
                timeout: .milliseconds(timeoutMs)
            )
        }

        let timedOut = statuses.isEmpty
        let statusesById = Dictionary(uniqueKeysWithValues: statuses)
        var resultStatus: [String: AgentStatus] = [:]
        for (threadId, status) in statuses {
            if let key = targetByThreadId[threadId] {
                resultStatus[key] = status
            }
        }
        try? await control.emitTurnItemCompleted(
            threadId: caller,
            turnId: invocation.turnId,
            item: .collabAgentToolCall(
                CollabAgentToolCallItem(
                    id: invocation.callId,
                    tool: .wait,
                    status: waitToolCallStatus(statusesById),
                    senderThreadId: caller,
                    receiverThreadIds: Array(statusesById.keys),
                    receiverAgents: waitReceiverAgents(statusesById, receiverAgents: receiverAgents),
                    agentsStates: statusesById
                )
            )
        )
        return WaitAgentResult(status: resultStatus, timedOut: timedOut)
    }
}

func waitToolCallStatus(_ statuses: [ThreadId: AgentStatus]) -> CollabAgentToolCallStatus {
    if statuses.values.contains(where: {
        if case .errored = $0 { return true }
        if case .notFound = $0 { return true }
        return false
    }) {
        return .failed
    }
    return .completed
}

func waitReceiverAgents(
    _ statuses: [ThreadId: AgentStatus],
    receiverAgents: [CollabAgentRef]
) -> [CollabAgentRef] {
    if statuses.isEmpty { return [] }
    var agents: [CollabAgentRef] = []
    var seen: Set<ThreadId> = []
    agents.reserveCapacity(statuses.count)
    for agent in receiverAgents {
        seen.insert(agent.threadId)
        if statuses[agent.threadId] != nil {
            agents.append(agent)
        }
    }
    var extras = statuses.keys
        .filter { !seen.contains($0) }
        .map { CollabAgentRef(threadId: $0) }
    extras.sort { $0.threadId.description < $1.threadId.description }
    agents.append(contentsOf: extras)
    return agents
}

