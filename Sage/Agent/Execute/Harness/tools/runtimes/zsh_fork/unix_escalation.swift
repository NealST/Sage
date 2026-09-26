//
//  unix_escalation.swift
//  ToolsRuntimes
//
//  Port of codex-rs/core/src/tools/runtimes/zsh_fork/unix_escalation.rs
//  (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  The escalation socket server waits for a dedicated crate. This file
//  keeps the zsh -c/-lc rewrite used on macOS.
//

import Foundation

public let ESCALATE_SOCKET_ENV_VAR = "CODEX_ESCALATE_SOCKET"

public func prepareUnifiedExecZshFork(
    command: [String],
    env: inout [String: String],
    zshPath: String = "/bin/zsh"
) -> PreparedUnifiedExecSpawn? {
    guard command.count >= 3 else { return nil }
    let executable = command[0]
    let flag = command[1]
    guard (executable.hasSuffix("/zsh") || executable == "zsh"),
          flag == "-c" || flag == "-lc" else {
        return nil
    }
    env[ESCALATE_SOCKET_ENV_VAR] = env[ESCALATE_SOCKET_ENV_VAR] ?? ""
    return PreparedUnifiedExecSpawn(command: [zshPath, flag, command[2]], env: env)
}
