//
//  send_message.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/handlers/multi_agents_v2/send_message.rs
//  (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Spec, argument parsing, and mailbox send are live when
//  LocalAgentControl is attached.
//

import CodexCore
import CodexProtocol

struct SendMessageHandler: CoreToolRuntime {
    func toolName() -> ToolName { ToolName(plain: "send_message") }
    func spec() -> ToolSpec { createSendMessageTool() }

    func handle(_ invocation: ToolInvocation) async throws -> any ToolOutput {
        let arguments = try functionArguments(invocation.payload)
        let args: SendMessageArgs = try parseArguments(arguments)
        return try await handleMessageStringTool(
            invocation: invocation,
            mode: .queueOnly,
            target: args.target,
            message: args.message
        )
    }
}
