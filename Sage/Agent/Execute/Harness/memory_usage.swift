//
//  memory_usage.swift
//  CodexCore
//
//  Port of codex-rs/core/src/memory_usage.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  `codex_memories_read` and session telemetry are not in Phase 7. The
//  command extractor is faithful; metric emission is a no-op until the
//  memories crate is ported.
//

import Foundation

public func emitMetricForToolRead(toolName: String, arguments: String, success: Bool) {
    _ = (shellScriptForInvocation(toolName: toolName, arguments: arguments), success)
}

public func shellScriptForInvocation(toolName: String, arguments: String) -> String? {
    guard toolName == "exec_command" else { return nil }
    struct ExecCommandArgs: Decodable {
        var cmd: String
    }
    return try? JSONDecoder().decode(ExecCommandArgs.self, from: Data(arguments.utf8)).cmd
}
