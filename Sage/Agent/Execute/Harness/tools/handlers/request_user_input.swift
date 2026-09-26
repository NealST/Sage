//
//  request_user_input.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/handlers/request_user_input.rs
//  (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Guardian retained-context recording waits for Phase 8. The handler
//  validates mode and invokes onRequestUserInput.
//

import CodexCore
import CodexProtocol
import Foundation

struct RequestUserInputHandler: CoreToolRuntime {
    var availableModes: [ModeKind]

    init(availableModes: [ModeKind] = [.plan]) {
        self.availableModes = availableModes
    }

    func toolName() -> ToolName { ToolName(plain: REQUEST_USER_INPUT_TOOL_NAME) }
    func spec() -> ToolSpec {
        createRequestUserInputTool(requestUserInputToolDescription(availableModes: availableModes))
    }
    func isBuiltinControlTool() -> Bool { true }

    func handle(_ invocation: ToolInvocation) async throws -> any ToolOutput {
        guard case .function(let arguments) = invocation.payload else {
            throw FunctionCallError.respondToModel(
                "\(REQUEST_USER_INPUT_TOOL_NAME) handler received unsupported payload"
            )
        }
        if !invocation.isRootThread {
            throw FunctionCallError.respondToModel(
                "request_user_input can only be used by the root thread"
            )
        }
        if let message = requestUserInputUnavailableMessage(
            mode: invocation.modeKind,
            availableModes: availableModes
        ) {
            throw FunctionCallError.respondToModel(message)
        }
        let parsed: RequestUserInputToolArgs = try parseArguments(arguments)
        let normalized = try normalizeRequestUserInputToolArgs(parsed)
        let args = RequestUserInputArgs(
            questions: normalized.questions,
            isBlocking: invocation.modeKind == .plan
        )
        guard let onRequest = invocation.onRequestUserInput else {
            throw FunctionCallError.respondToModel(
                "request_user_input is not wired (Phase 5 Session)"
            )
        }
        guard let response = await onRequest(args) else {
            throw FunctionCallError.respondToModel(
                "\(REQUEST_USER_INPUT_TOOL_NAME) was cancelled before receiving a response"
            )
        }
        let data = try JSONEncoder().encode(response)
        let content = String(data: data, encoding: .utf8) ?? "{}"
        return boxedToolOutput(FunctionToolOutput.fromText(content, success: true))
    }
}
