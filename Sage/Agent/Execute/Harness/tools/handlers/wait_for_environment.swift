//
//  wait_for_environment.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/handlers/wait_for_environment.rs
//  (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Environment attach / Phase 9 wiring waits. The handler forwards through
//  onWaitForEnvironment.
//

import CodexCore
import CodexProtocol

let WAIT_FOR_ENVIRONMENT_TOOL_NAME = "wait_for_environment"

struct WaitForEnvironmentHandler: CoreToolRuntime {
    var descriptionText: String

    init(description: String = "Wait until the requested environment is ready.") {
        self.descriptionText = description
    }

    func toolName() -> ToolName { ToolName(plain: WAIT_FOR_ENVIRONMENT_TOOL_NAME) }
    func spec() -> ToolSpec {
        .function(
            ResponsesApiTool(
                name: WAIT_FOR_ENVIRONMENT_TOOL_NAME,
                description: descriptionText,
                strict: false,
                parameters: .object(
                    [
                        "environment_id": .string(
                            "Environment id from <environment_context> to wait for."
                        )
                    ],
                    additionalProperties: false
                )
            )
        )
    }

    func handle(_ invocation: ToolInvocation) async throws -> any ToolOutput {
        guard case .function = invocation.payload else {
            throw FunctionCallError.respondToModel(
                "wait_for_environment handler received unsupported payload"
            )
        }
        guard let onWait = invocation.onWaitForEnvironment else {
            throw FunctionCallError.respondToModel(
                "wait_for_environment is not wired (Phase 9)"
            )
        }
        guard let output = await onWait() else {
            throw FunctionCallError.respondToModel(
                "wait_for_environment was cancelled before receiving a response"
            )
        }
        return boxedToolOutput(FunctionToolOutput.fromText(output, success: true))
    }
}
