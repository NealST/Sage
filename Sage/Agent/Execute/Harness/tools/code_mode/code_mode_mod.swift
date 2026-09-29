//
//  code_mode_mod.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/code_mode/mod.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Public names and the exec-tool predicate are faithful. Execute / wait
//  / delegate handlers wait on Session / CodeModeSession.
//  R4a: basename `mod.swift` already belongs to tools/mod.swift.
//

import CodexProtocol

let PUBLIC_TOOL_NAME = "exec"
let WAIT_TOOL_NAME = "wait"
let DEFAULT_EXEC_YIELD_TIME_MS: UInt64 = 10_000
let DEFAULT_WAIT_YIELD_TIME_MS: UInt64 = 10_000

func isExecToolName(_ toolName: ToolName) -> Bool {
    toolName.isDefaultNamespace() && toolName.name == PUBLIC_TOOL_NAME
}
