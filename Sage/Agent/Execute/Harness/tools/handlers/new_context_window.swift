//
//  new_context_window.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/handlers/new_context_window.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import CodexCore
import CodexProtocol

let NEW_CONTEXT_WINDOW_MESSAGE =
    "A new context window will start without summarizing conversation history."

struct NewContextWindowHandler: CoreToolRuntime {
    func toolName() -> ToolName { ToolName(plain: NEW_CONTEXT_WINDOW_TOOL_NAME) }
    func spec() -> ToolSpec { createNewContextWindowTool() }

    func handle(_ invocation: ToolInvocation) async throws -> any ToolOutput {
        guard case .function = invocation.payload else {
            throw FunctionCallError.respondToModel("new_context handler received unsupported payload")
        }
        invocation.onNewContextWindow?()
        return boxedToolOutput(FunctionToolOutput.fromText(NEW_CONTEXT_WINDOW_MESSAGE, success: true))
    }
}
