//
//  test_sync_spec.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/handlers/test_sync_spec.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//

func createTestSyncTool() -> ToolSpec {
    let barrierProperties: [String: JsonSchema] = [
        "id": .string("Identifier shared by concurrent calls that should rendezvous"),
        "participants": .number(
            "Number of tool calls that must arrive before the barrier opens"
        ),
        "timeout_ms": .number("Maximum barrier wait in milliseconds. Defaults to 1000."),
    ]
    return .function(
        ResponsesApiTool(
            name: "test_sync_tool",
            description: "Internal synchronization helper used by Codex integration tests.",
            strict: false,
            parameters: .object(
                [
                    "sleep_before_ms": .number("Delay before any other action. Defaults to no delay."),
                    "sleep_after_ms": .number(
                        "Delay after completing the barrier. Defaults to no delay."
                    ),
                    "barrier": .object(
                        barrierProperties,
                        required: ["id", "participants"],
                        additionalProperties: false
                    ),
                    "wait_for_git_enrichment": .boolean(
                        "Wait for Git enrichment for the current turn to finish, subject to a timeout."
                    ),
                ],
                additionalProperties: false
            )
        )
    )
}
