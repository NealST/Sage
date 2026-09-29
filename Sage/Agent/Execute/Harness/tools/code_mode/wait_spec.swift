//
//  wait_spec.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/code_mode/wait_spec.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Name, required `cell_id`, and parameter keys are faithful. Catalog
//  parameter overrides wait on catalog_parameters.
//

func createWaitTool(
    descriptionOverride: String? = nil,
    parametersOverride: String? = nil
) -> ToolSpec {
    _ = parametersOverride
    let description = descriptionOverride ?? """
        Waits on a yielded `\(PUBLIC_TOOL_NAME)` cell and returns new output or completion.
        """
    let properties: [String: JsonSchema] = [
        "cell_id": .string("Identifier of the running exec cell."),
        "yield_time_ms": .number("Wait before yielding more output. Defaults to 10000 ms."),
        "max_tokens": .number(
            "Output token budget for this wait call. Defaults to 10000 tokens."
        ),
        "terminate": .boolean(
            "True stops the running exec cell; false or omitted waits for output."
        ),
    ]
    return .function(
        ResponsesApiTool(
            name: WAIT_TOOL_NAME,
            description: description,
            strict: false,
            parameters: .object(properties, required: ["cell_id"], additionalProperties: false)
        )
    )
}
