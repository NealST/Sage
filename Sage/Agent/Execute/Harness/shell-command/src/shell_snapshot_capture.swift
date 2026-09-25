//
//  shell_snapshot_capture.swift
//  CodexShellCommand
//
//  Port of codex-rs/shell-command/src/shell_snapshot_capture.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: partial
//
//  Login-shell capture is deferred until unified_exec/PTY lands. The
//  function shape is kept so callers can compile.
//

public func captureShellSnapshot(_ shell: DetectedShell) async throws -> ShellSnapshot {
    ShellSnapshot(shellType: shell.shellType)
}
