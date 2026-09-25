//
//  powershell.swift
//  CodexShellCommand
//
//  Port of codex-rs/shell-command/src/powershell.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  macOS only needs bash/zsh/sh. The same file exists so parse_command can
//  still recognize `pwsh -Command` wrappers and return nil for script
//  extraction rather than inventing a PowerShell parser.
//

public func extractPowershellCommand(_ command: [String]) -> (shell: String, script: String)? {
    guard command.count >= 2 else { return nil }
    guard detectShellType(command[0]) == .powerShell else { return nil }
    if let index = command.firstIndex(where: { $0 == "-Command" || $0 == "-C" || $0 == "-c" }),
       command.indices.contains(index + 1) {
        return (command[0], command[index + 1])
    }
    return nil
}
