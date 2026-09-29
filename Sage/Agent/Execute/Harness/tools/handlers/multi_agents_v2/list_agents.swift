//
//  list_agents.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/handlers/multi_agents_v2/list_agents.rs
//  (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Spec, argument parsing, and registry listing are live when
//  LocalAgentControl is attached to the invocation.
//

import CodexCore
import CodexProtocol

struct ListAgentsArgs: Decodable, Equatable, Sendable {
    var pathPrefix: String?

    enum CodingKeys: String, CodingKey {
        case pathPrefix = "path_prefix"
    }
}

struct ListedAgent: Encodable, Equatable, Sendable {
    var agentName: String
    var agentStatus: AgentStatus

    enum CodingKeys: String, CodingKey {
        case agentName = "agent_name"
        case agentStatus = "agent_status"
    }
}

struct ListAgentsResult: Encodable, Equatable, Sendable, ToolOutput {
    var agents: [ListedAgent]

    func logOutput() -> String { toolOutputJsonText(self, toolName: "list_agents") }
    func successForLogging() -> Bool { true }
    func toResponseItem(callId: String, payload: ToolPayload) -> ResponseInputItem {
        toolOutputResponseItem(
            callId: callId, payload: payload, value: self, success: true, toolName: "list_agents")
    }
    func codeModeResult(_ payload: ToolPayload) -> HarnessJSON {
        toolOutputCodeModeResult(self, toolName: "list_agents")
    }
}

struct ListAgentsHandler: CoreToolRuntime {
    func toolName() -> ToolName { ToolName(plain: "list_agents") }
    func spec() -> ToolSpec { createListAgentsTool() }

    func handle(_ invocation: ToolInvocation) async throws -> any ToolOutput {
        let arguments = try functionArguments(invocation.payload)
        let args: ListAgentsArgs = try parseArguments(arguments)
        let control = try requireLocalAgentControl(invocation)
        let caller = try requireCallerThreadId(invocation)
        let agents = try await control.list(
            caller: caller,
            parent: invocation.parentThreadId,
            source: invocation.sessionSource,
            pathPrefix: args.pathPrefix
        )
        return ListAgentsResult(
            agents: agents.map { agent in
                ListedAgent(
                    agentName: agent.metadata.agentPath?.asStr ?? agent.threadId.description,
                    agentStatus: agent.status
                )
            }
        )
    }
}
