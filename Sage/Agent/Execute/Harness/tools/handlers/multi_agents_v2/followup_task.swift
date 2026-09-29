//
//  followup_task.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/handlers/multi_agents_v2/followup_task.rs
//  (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Spec, argument parsing, and mailbox send are live when
//  LocalAgentControl is attached.
//

import CodexCore
import CodexProtocol

struct FollowupTaskHandler: CoreToolRuntime {
    func toolName() -> ToolName { ToolName(plain: "followup_task") }
    func spec() -> ToolSpec { createFollowupTaskTool() }

    func handle(_ invocation: ToolInvocation) async throws -> any ToolOutput {
        let arguments = try functionArguments(invocation.payload)
        let args: FollowupTaskArgs = try parseArguments(arguments)
        return try await handleMessageStringTool(
            invocation: invocation,
            mode: .triggerTurn,
            target: args.target,
            message: args.message
        )
    }
}
