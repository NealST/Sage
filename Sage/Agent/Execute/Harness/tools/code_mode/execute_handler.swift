//
//  execute_handler.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/code_mode/execute_handler.rs
//  (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Spec and payload checks are live. Cell execution waits on
//  CodeModeSession / Session.
//

import CodexCore
import CodexProtocol
import Foundation

struct ExecSourceArgs: Equatable, Sendable {
    var code: String
    var yieldTimeMs: UInt64?
    var maxOutputTokens: UInt64?
}

func parseExecSource(_ code: String) -> ExecSourceArgs {
    ExecSourceArgs(code: code, yieldTimeMs: nil, maxOutputTokens: nil)
}

struct CodeModeExecuteHandler: CoreToolRuntime {
    var nestedToolSpecs: [ToolSpec]

    init(nestedToolSpecs: [ToolSpec] = []) {
        self.nestedToolSpecs = nestedToolSpecs
    }

    func toolName() -> ToolName { ToolName(plain: PUBLIC_TOOL_NAME) }
    func spec() -> ToolSpec { createCodeModeTool() }

    func handle(_ invocation: ToolInvocation) async throws -> any ToolOutput {
        let source: String
        switch invocation.payload {
        case .custom(let input):
            source = input
        case .function(let arguments):
            source = arguments
        case .toolSearch:
            throw FunctionCallError.respondToModel(
                "exec handler received unsupported payload"
            )
        }
        _ = parseExecSource(source)
        throw FunctionCallError.respondToModel("exec waits on CodeModeSession / Session")
    }
}
