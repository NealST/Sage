//
//  interrupt_agent.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/handlers/multi_agents_v2/interrupt_agent.rs
//  (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Spec, argument parsing, V2 validation, and mailbox interrupt are live
//  when LocalAgentControl is attached. ThreadManager stop is still pending.
//

import CodexCore
import CodexProtocol

struct InterruptAgentArgs: Decodable, Equatable, Sendable {
    var target: String
}

struct InterruptAgentResult: Encodable, Equatable, Sendable, ToolOutput {
    var previousStatus: AgentStatus

    enum CodingKeys: String, CodingKey {
        case previousStatus = "previous_status"
    }

    func logOutput() -> String { toolOutputJsonText(self, toolName: "interrupt_agent") }
    func successForLogging() -> Bool { true }
    func toResponseItem(callId: String, payload: ToolPayload) -> ResponseInputItem {
        toolOutputResponseItem(
            callId: callId, payload: payload, value: self, success: true, toolName: "interrupt_agent")
    }
    func codeModeResult(_ payload: ToolPayload) -> HarnessJSON {
        toolOutputCodeModeResult(self, toolName: "interrupt_agent")
    }
}

struct InterruptAgentHandler: CoreToolRuntime {
    func toolName() -> ToolName { ToolName(plain: "interrupt_agent") }
    func spec() -> ToolSpec { createInterruptAgentToolV2() }

    func handle(_ invocation: ToolInvocation) async throws -> any ToolOutput {
        let arguments = try functionArguments(invocation.payload)
        let args: InterruptAgentArgs = try parseArguments(arguments)
        let control = try requireLocalAgentControl(invocation)
        let caller = try requireCallerThreadId(invocation)
        let target: AgentTarget
        if let threadId = try? ThreadId.fromString(args.target) {
            target = .id(threadId)
        } else {
            target = .reference(args.target)
        }
        let snapshot = try await control.interrupt(
            caller: caller,
            target: target,
            version: .v2
        )
        return InterruptAgentResult(previousStatus: snapshot.status() ?? .notFound)
    }
}
