//
//  command_safety_mod.swift
//  CodexShellCommand
//
//  Port of codex-rs/shell-command/src/command_safety/mod.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  R4a: basename `mod.swift` would collide inside CodexShellCommand if
//  another crate file used it; this file is `command_safety/mod.swift`.
//  PowerShell parsers stay test-only upstream; production classification
//  uses `is_dangerous_command`.
//
