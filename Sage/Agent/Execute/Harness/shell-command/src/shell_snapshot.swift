//
//  shell_snapshot.swift
//  CodexShellCommand
//
//  Port of codex-rs/shell-command/src/shell_snapshot.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: partial
//
//  Snapshot types and the capture/render entry points. Full capture
//  (login shell + credential redaction) is in the sibling snapshot files.
//

public struct ShellSnapshot: Equatable, Sendable {
    public var shellType: ShellType
    public var exports: [String: String]
    public var aliases: [String: String]
    public var functions: [String: String]

    public init(
        shellType: ShellType,
        exports: [String: String] = [:],
        aliases: [String: String] = [:],
        functions: [String: String] = [:]
    ) {
        self.shellType = shellType
        self.exports = exports
        self.aliases = aliases
        self.functions = functions
    }
}
