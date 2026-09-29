//
//  command_runner.swift
//  CodexHooks
//
//  Port of codex-rs/hooks/src/engine/command_runner.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  CommandHookRuntime process spawn waits on a Process runner. Types used
//  by the engine are kept so callers can construct a no-op runtime.
//

import CodexProtocol
import Foundation

public struct CommandHookRuntime: Sendable {
    public var shell: CommandShell

    public init(shell: CommandShell) {
        self.shell = shell
    }

    public func reconfigured(_ shell: CommandShell) -> CommandHookRuntime {
        CommandHookRuntime(shell: shell)
    }

    public func shutdown() async {}

    public func runCommand() async throws -> HandlerRunResult {
        throw CodexErr.unsupportedOperation("CommandHookRuntime.run_command waits on process spawn")
    }
}

public func runCommand() async throws -> HandlerRunResult {
    throw CodexErr.unsupportedOperation("run_command waits on process spawn")
}
