//
//  command_canonicalization.swift
//  Sage
//
//  Port of codex-rs/core/src/command_canonicalization.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  Canonicalizes argv for approval-cache matching across wrapper paths.
//

import CodexShellCommand

let CANONICAL_BASH_SCRIPT_PREFIX = "__codex_shell_script__"
let CANONICAL_POWERSHELL_SCRIPT_PREFIX = "__codex_powershell_script__"

func canonicalizeCommandForApproval(_ command: [String]) -> [String] {
    if let commands = parseShellLcPlainCommands(command), commands.count == 1 {
        return commands[0]
    }
    if let (_, script) = extractBashCommand(command) {
        let shellMode = command.indices.contains(1) ? command[1] : ""
        return [CANONICAL_BASH_SCRIPT_PREFIX, shellMode, script]
    }
    if let (_, script) = extractPowershellCommand(command) {
        return [CANONICAL_POWERSHELL_SCRIPT_PREFIX, script]
    }
    return command
}
