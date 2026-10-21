//
//  zsh_fork.swift
//  ToolsRuntimes
//
//  Port of codex-rs/core/src/tools/runtimes/zsh_fork.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Escalation-server process management waits for a dedicated crate. This
//  file detects a wrapped `zsh -c/-lc` command and rewrites it.
//

import Foundation

public struct PreparedUnifiedExecSpawn: Equatable, Sendable {
    public var command: [String]
    public var env: [String: String]
}

public func maybePrepareUnifiedExec(
    command: [String],
    env: inout [String: String],
    zshPath: String = "/bin/zsh"
) -> PreparedUnifiedExecSpawn? {
    prepareUnifiedExecZshFork(command: command, env: &env, zshPath: zshPath)
}
