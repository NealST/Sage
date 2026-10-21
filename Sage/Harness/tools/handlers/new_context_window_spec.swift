//
//  new_context_window_spec.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/handlers/new_context_window_spec.rs
//  (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//

let NEW_CONTEXT_WINDOW_TOOL_NAME = "new_context"

func createNewContextWindowTool() -> ToolSpec {
    .function(
        ResponsesApiTool(
            name: NEW_CONTEXT_WINDOW_TOOL_NAME,
            description: "Start a new context window. Does not clear, reset, or otherwise affect environment state.",
            strict: false,
            parameters: .object([:], additionalProperties: false)
        )
    )
}
