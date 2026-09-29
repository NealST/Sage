//
//  execute_spec.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/code_mode/execute_spec.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Name, grammar, and freeform kind are faithful. Description text waits
//  on the code_mode crate's `build_exec_tool_description`.
//

let CODE_MODE_FREEFORM_GRAMMAR = """

start: pragma_source | plain_source
pragma_source: PRAGMA_LINE NEWLINE SOURCE
plain_source: SOURCE

PRAGMA_LINE: /[ \\t]*\\/\\/ @exec:[^\\r\\n]*/
NEWLINE: /\\r?\\n/
SOURCE: /[\\s\\S]+/
"""

func createCodeModeTool(
    description: String = "Execute a code-mode cell.",
    defaultExecYieldTimeMs: UInt64 = DEFAULT_EXEC_YIELD_TIME_MS,
    codeModeOnly: Bool = true
) -> ToolSpec {
    _ = defaultExecYieldTimeMs
    _ = codeModeOnly
    return .freeform(
        FreeformTool(
            name: PUBLIC_TOOL_NAME,
            description: description,
            format: CODE_MODE_FREEFORM_GRAMMAR
        )
    )
}
