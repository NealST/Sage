//
//  send_message_to_user_async.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/handlers/send_message_to_user_async.rs
//  (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import CodexCore
import CodexProtocol
import Foundation

let SEND_MESSAGE_TO_USER_ASYNC_TOOL_NAME = "send_message_to_user_async"

struct SendMessageToUserAsyncArgs: Decodable {
    var message: String
}

struct SendMessageToUserAsyncHandler: CoreToolRuntime {
    func toolName() -> ToolName { ToolName(plain: SEND_MESSAGE_TO_USER_ASYNC_TOOL_NAME) }
    func isBuiltinControlTool() -> Bool { true }

    func spec() -> ToolSpec {
        .function(
            ResponsesApiTool(
                name: SEND_MESSAGE_TO_USER_ASYNC_TOOL_NAME,
                description: "Send a concise message that needs the user's attention during ongoing work. The tool returns immediately without ending the turn or waiting for a reply; any reply arrives asynchronously as a new user message. Use this tool to report a critical blocker or a finding that may change the task's direction, or to answer a user question or status request received while work is still in progress. Use this tool when a message needs the user's immediate attention; use commentary for routine progress and intermediate context. Use clear formatting, such as bolding questions, to make requests easy to notice and answer.",
                strict: false,
                parameters: .object(
                    ["message": .string("The concise question or update to send to the user.")],
                    required: ["message"],
                    additionalProperties: false
                )
            )
        )
    }

    func handle(_ invocation: ToolInvocation) async throws -> any ToolOutput {
        guard case .function(let arguments) = invocation.payload else {
            throw FunctionCallError.respondToModel(
                "\(SEND_MESSAGE_TO_USER_ASYNC_TOOL_NAME) handler received unsupported payload"
            )
        }
        let args: SendMessageToUserAsyncArgs = try parseArguments(arguments)
        let message = args.message.trimmingCharacters(in: .whitespacesAndNewlines)
        if message.isEmpty {
            throw FunctionCallError.respondToModel("message must not be empty")
        }
        invocation.onAsyncUserMessage?(message)
        return boxedToolOutput(FunctionToolOutput.fromText(#"{"accepted":true}"#, success: true))
    }
}
