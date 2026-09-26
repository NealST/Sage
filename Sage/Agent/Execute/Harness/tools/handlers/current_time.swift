//
//  current_time.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/handlers/current_time.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Time provider waits for Phase 5 session services. The handler uses
//  ToolInvocation.clock.
//

import CodexCore
import CodexProtocol
import Foundation

let CLOCK_NAMESPACE = "clock"
let CURRENT_TIME_TOOL_NAME = "curr_time"

struct CurrentTimeOutput: ToolOutput {
    var formattedTime: String

    func logOutput() -> String { formattedTime }
    func successForLogging() -> Bool { true }

    func toResponseItem(callId: String, payload: ToolPayload) -> ResponseInputItem {
        FunctionToolOutput.fromText(formattedTime, success: true)
            .toResponseItem(callId: callId, payload: payload)
    }

    func codeModeResult(_ payload: ToolPayload) -> HarnessJSON {
        .object(["current_time": .string(formattedTime)])
    }
}

struct CurrentTimeHandler: CoreToolRuntime {
    func toolName() -> ToolName {
        ToolName(namespaced: CLOCK_NAMESPACE, name: CURRENT_TIME_TOOL_NAME)
    }

    func spec() -> ToolSpec {
        .namespace(
            ResponsesApiNamespace(
                name: CLOCK_NAMESPACE,
                description: "Tools for reading and waiting on time.",
                tools: [
                    ResponsesApiNamespaceTool(
                        function: ResponsesApiTool(
                            name: CURRENT_TIME_TOOL_NAME,
                            description: "Return the current time in UTC.",
                            strict: false,
                            parameters: .object([:], additionalProperties: false)
                        )
                    )
                ]
            )
        )
    }

    func isBuiltinControlTool() -> Bool { true }

    func handle(_ invocation: ToolInvocation) async throws -> any ToolOutput {
        guard case .function = invocation.payload else {
            throw FunctionCallError.respondToModel(
                "\(CURRENT_TIME_TOOL_NAME) handler received unsupported payload"
            )
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss 'UTC'"
        return boxedToolOutput(CurrentTimeOutput(formattedTime: formatter.string(from: invocation.clock())))
    }
}
