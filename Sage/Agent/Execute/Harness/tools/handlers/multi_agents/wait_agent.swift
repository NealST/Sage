//
//  wait_agent.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/handlers/multi_agents/wait.rs
//  (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Spec, argument parsing, and mailbox status poll are live when
//  LocalAgentControl is attached. Live watch loops wait on ThreadManager.
//

import CodexCore
import CodexProtocol

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
    func toolName() -> ToolName { ToolName(namespaced: MULTI_AGENT_V1_NAMESPACE, name: "wait_agent") }
    func spec() -> ToolSpec { createWaitAgentToolV1() }
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
        _ = try clampWaitTimeoutMs(args.timeoutMs)
        let control = try requireLocalAgentControl(invocation)
        var status: [String: AgentStatus] = [:]
        var allFinal = true
        for target in targets {
            let current = await control.getStatus(target)
            status[target.description] = current
            if !isFinal(current) {
                allFinal = false
            }
        }
        return WaitAgentResult(status: status, timedOut: !allFinal)
    }
}
