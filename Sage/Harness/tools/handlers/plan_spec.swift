//
//  plan_spec.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/handlers/plan_spec.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//

func createUpdatePlanTool() -> ToolSpec {
    let planItem: [String: JsonSchema] = [
        "step": .string("Task step text."),
        "status": .stringEnum(["pending", "in_progress", "completed"], description: "Step status."),
    ]
    let properties: [String: JsonSchema] = [
        "explanation": .string("Optional explanation for this plan update."),
        "plan": .array(
            .object(planItem, required: ["step", "status"], additionalProperties: false),
            description: "The list of steps"
        ),
    ]
    return .function(
        ResponsesApiTool(
            name: "update_plan",
            description: """
            Updates the task plan.
            Provide an optional explanation and a list of plan items, each with a step and status.
            At most one step can be in_progress at a time.
            """,
            strict: false,
            parameters: .object(properties, required: ["plan"], additionalProperties: false)
        )
    )
}
