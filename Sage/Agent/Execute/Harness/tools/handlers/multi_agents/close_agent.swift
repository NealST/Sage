//
//  close_agent.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/handlers/multi_agents/close_agent.rs
//  (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Spec, argument parsing, and registry close are live. Persisted
//  spawn-edge updates wait on ThreadManager.
//

import CodexCore
import CodexProtocol

struct CloseAgentArgs: Decodable, Equatable, Sendable {
    var target: String
}

struct CloseAgentResult: Encodable, Equatable, Sendable, ToolOutput {
    var previousStatus: AgentStatus

    enum CodingKeys: String, CodingKey {
        case previousStatus = "previous_status"
    }

    func logOutput() -> String { toolOutputJsonText(self, toolName: "close_agent") }
    func successForLogging() -> Bool { true }
    func toResponseItem(callId: String, payload: ToolPayload) -> ResponseInputItem {
        toolOutputResponseItem(
            callId: callId, payload: payload, value: self, success: true, toolName: "close_agent")
    }
    func codeModeResult(_ payload: ToolPayload) -> HarnessJSON {
        toolOutputCodeModeResult(self, toolName: "close_agent")
    }
}

struct CloseAgentHandler: CoreToolRuntime {
    func toolName() -> ToolName { ToolName(namespaced: MULTI_AGENT_V1_NAMESPACE, name: "close_agent") }
    func spec() -> ToolSpec { createCloseAgentToolV1() }
    func searchInfo() -> ToolSearchInfo? {
        multiAgentToolSearchInfo(
            searchText: "close_agent close shutdown stop agent subagent thread status target",
            spec: spec()
        )
    }

    func handle(_ invocation: ToolInvocation) async throws -> any ToolOutput {
        let arguments = try functionArguments(invocation.payload)
        let args: CloseAgentArgs = try parseArguments(arguments)
        let agentId = try parseAgentIdTarget(args.target)
        let control = try requireLocalAgentControl(invocation)
        let snapshot = try await control.closeAgent(agentId)
        return CloseAgentResult(previousStatus: snapshot.status() ?? .notFound)
    }
}
