//
//  get_context_remaining.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/handlers/get_context_remaining.rs
//  (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import CodexCore
import CodexProtocol

struct GetContextRemainingOutput: ToolOutput {
    var tokensLeft: Int64?

    func fragment() -> String {
        if let tokensLeft {
            return "Tokens remaining in the current context window: \(tokensLeft)."
        }
        return "Remaining context-window tokens are unavailable."
    }

    func logOutput() -> String { fragment() }
    func successForLogging() -> Bool { true }

    func toResponseItem(callId: String, payload: ToolPayload) -> ResponseInputItem {
        FunctionToolOutput.fromText(fragment(), success: true).toResponseItem(callId: callId, payload: payload)
    }

    func codeModeResult(_ payload: ToolPayload) -> HarnessJSON {
        if let tokensLeft {
            return .object(["tokens_left": .int(tokensLeft)])
        }
        return .object(["tokens_left": .null])
    }
}

struct GetContextRemainingHandler: CoreToolRuntime {
    func toolName() -> ToolName { ToolName(plain: GET_CONTEXT_REMAINING_TOOL_NAME) }
    func spec() -> ToolSpec { createGetContextRemainingTool() }

    func handle(_ invocation: ToolInvocation) async throws -> any ToolOutput {
        guard case .function = invocation.payload else {
            throw FunctionCallError.respondToModel(
                "get_context_remaining handler received unsupported payload"
            )
        }
        return boxedToolOutput(GetContextRemainingOutput(tokensLeft: invocation.tokensRemaining))
    }
}
