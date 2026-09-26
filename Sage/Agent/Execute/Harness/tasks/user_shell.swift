//
//  user_shell.swift
//  Sage
//
//  Port of codex-rs/core/src/tasks/user_shell.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Execution goes through CodexCore spawn/exec. This records the fragment.
//

import CodexCore
import Foundation

enum UserShellCommandMode: Equatable, Sendable {
    case login
    case direct
}

final class UserShellCommandTask: @unchecked Sendable {
    var command: String
    var mode: UserShellCommandMode

    init(command: String, mode: UserShellCommandMode = .direct) {
        self.command = command
        self.mode = mode
    }
}

func executeUserShellCommand(
    _ command: String,
    exitCode: Int32,
    duration: TimeInterval,
    output: String
) -> ContextUserShellCommand {
    ContextUserShellCommand(
        command: command,
        exitCode: exitCode,
        duration: duration,
        output: output
    )
}
