//
//  resume_agent.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/handlers/multi_agents/resume_agent.rs
//  (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Spec, argument parsing, and registry rematerialize are live when
//  LocalAgentControl is attached. Rollout restore waits on ThreadManager.
//

import CodexCore
import CodexProtocol

struct ResumeAgentArgs: Decodable, Equatable, Sendable {
    var id: String
}

struct ResumeAgentResult: Encodable, Equatable, Sendable, ToolOutput {
    var status: AgentStatus

    func logOutput() -> String { toolOutputJsonText(self, toolName: "resume_agent") }
    func successForLogging() -> Bool { true }
    func toResponseItem(callId: String, payload: ToolPayload) -> ResponseInputItem {
        toolOutputResponseItem(
            callId: callId, payload: payload, value: self, success: true, toolName: "resume_agent")
    }
    func codeModeResult(_ payload: ToolPayload) -> HarnessJSON {
        toolOutputCodeModeResult(self, toolName: "resume_agent")
    }
}

struct ResumeAgentHandler: CoreToolRuntime {
    func toolName() -> ToolName { ToolName(namespaced: MULTI_AGENT_V1_NAMESPACE, name: "resume_agent") }
    func spec() -> ToolSpec { createResumeAgentTool() }
    func searchInfo() -> ToolSearchInfo? {
        multiAgentToolSearchInfo(
            searchText: "resume_agent resume reopen closed agent subagent thread id target",
            spec: spec()
        )
    }

    func handle(_ invocation: ToolInvocation) async throws -> any ToolOutput {
        let arguments = try functionArguments(invocation.payload)
        let args: ResumeAgentArgs = try parseArguments(arguments)
        let agentId = try parseAgentIdTarget(args.id)
        let control = try requireLocalAgentControl(invocation)
        do {
            let (agent, _) = try await control.resumeAgent(
                threadId: agentId,
                source: invocation.sessionSource
            )
            return ResumeAgentResult(status: agent.status)
        } catch let err as CodexErr {
            throw collabAgentError(agentId: agentId, err: err)
        }
    }
}
