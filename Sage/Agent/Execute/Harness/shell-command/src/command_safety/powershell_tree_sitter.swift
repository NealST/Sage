//
//  powershell_tree_sitter.swift
//  CodexShellCommand
//
//  Port of codex-rs/shell-command/src/command_safety/powershell_tree_sitter.rs
//  (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Production command classification does not compile the PowerShell
//  tree-sitter parser on macOS.
//

func tryParsePowershellCommandsTreeSitter(_: String) -> [[String]]? {
    nil
}
