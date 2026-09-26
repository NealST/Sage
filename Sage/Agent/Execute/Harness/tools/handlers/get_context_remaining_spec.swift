//
//  get_context_remaining_spec.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/handlers/get_context_remaining_spec.rs
//  (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//

import CodexProtocol

let GET_CONTEXT_REMAINING_TOOL_NAME = "get_context_remaining"

func createGetContextRemainingTool() -> ToolSpec {
    .function(
        ResponsesApiTool(
            name: GET_CONTEXT_REMAINING_TOOL_NAME,
            description: "Get the remaining tokens in the current context window.",
            strict: false,
            parameters: .object([:], additionalProperties: false),
            outputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "tokens_left": .object([
                        "description": .string(
                            "Remaining tokens in the current context window, or null when unavailable."
                        )
                    ])
                ]),
            ])
        )
    )
}
