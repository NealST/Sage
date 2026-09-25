//
//  windows_dangerous_commands.swift
//  CodexShellCommand
//
//  Port of codex-rs/shell-command/src/command_safety/windows_dangerous_commands.rs
//  (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Windows dangerous-command table. Host classification is POSIX, so these
//  predicates stay false unless an explicit Windows platform is requested.
//

func isDangerousCommandWindows(_: [String]) -> Bool {
    false
}

func isDangerousPowershellWords(_: [String]) -> Bool {
    false
}
