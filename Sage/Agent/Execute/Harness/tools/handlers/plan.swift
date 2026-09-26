//
//  plan.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/handlers/plan.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Session.send_event waits for Phase 5. The handler invokes onPlanUpdate.
//

import CodexCore
import CodexProtocol

let PLAN_UPDATED_MESSAGE = "Plan updated"

struct PlanToolOutput: ToolOutput {
    func logOutput() -> String { PLAN_UPDATED_MESSAGE }
    func successForLogging() -> Bool { true }

    func toResponseItem(callId: String, payload: ToolPayload) -> ResponseInputItem {
        var output = FunctionCallOutputPayload.fromText(PLAN_UPDATED_MESSAGE)
        output.success = true
        return .functionCallOutput(callId: callId, output: output)
    }

    func codeModeResult(_ payload: ToolPayload) -> HarnessJSON { .object([:]) }
}

struct PlanHandler: CoreToolRuntime {
    func toolName() -> ToolName { ToolName(plain: "update_plan") }
    func spec() -> ToolSpec { createUpdatePlanTool() }
    func isBuiltinControlTool() -> Bool { true }

    func handle(_ invocation: ToolInvocation) async throws -> any ToolOutput {
        guard case .function(let arguments) = invocation.payload else {
            throw FunctionCallError.respondToModel("update_plan handler received unsupported payload")
        }
        if invocation.modeKind == .plan {
            throw FunctionCallError.respondToModel(
                "update_plan is a TODO/checklist tool and is not allowed in Plan mode"
            )
        }
        let args: UpdatePlanArgs
        do {
            args = try parseArguments(arguments)
        } catch {
            throw FunctionCallError.respondToModel("failed to parse function arguments: \(error)")
        }
        invocation.onPlanUpdate?(args)
        return boxedToolOutput(PlanToolOutput())
    }
}
