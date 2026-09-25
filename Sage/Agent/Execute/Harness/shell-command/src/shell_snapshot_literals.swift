//
//  shell_snapshot_literals.swift
//  CodexShellCommand
//
//  Port of codex-rs/shell-command/src/shell_snapshot_literals.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: partial
//
//  Literal assignment detection used when a snapshot line is safe to replay.
//

public func isLiteralAssignmentValue(_ value: String) -> Bool {
    !value.contains(where: { "$`!".contains($0) })
}
