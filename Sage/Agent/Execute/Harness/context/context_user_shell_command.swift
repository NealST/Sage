//
//  context_user_shell_command.swift
//  CodexCore
//
//  Port of codex-rs/core/src/context/user_shell_command.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//

import CodexProtocol
import Foundation

public struct ContextUserShellCommand: ContextualUserFragment, Equatable, Sendable {
    public var command: String
    public var exitCode: Int32
    public var durationSeconds: Double
    public var output: String

    public init(command: String, exitCode: Int32, duration: TimeInterval, output: String) {
        self.command = command
        self.exitCode = exitCode
        self.durationSeconds = duration
        self.output = output
    }

    public var contentKind: ContentItemKind { ContentItemKind("shell.user_command") }
    public var role: String { "user" }
    public var openMarker: String { "<user_shell_command>" }
    public var closeMarker: String { "</user_shell_command>" }
    public var body: String {
        """

        <command>
        \(command)
        </command>
        <result>
        Exit code: \(exitCode)
        Duration: \(String(format: "%.4f", durationSeconds)) seconds
        Output:
        \(output)
        </result>
        """
    }
}
