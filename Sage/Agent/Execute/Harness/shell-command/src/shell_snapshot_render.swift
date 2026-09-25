//
//  shell_snapshot_render.swift
//  CodexShellCommand
//
//  Port of codex-rs/shell-command/src/shell_snapshot_render.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: partial
//
//  Renders captured exports as shell assignments, skipping credential names.
//

import Foundation

public func renderShellSnapshot(_ snapshot: ShellSnapshot) -> String {
    snapshot.exports
        .sorted { $0.key < $1.key }
        .filter { !looksLikeCredentialName($0.key) }
        .map { key, value in "export \(key)=\(posixShlexQuotePublic(value))" }
        .joined(separator: "\n")
}

private func posixShlexQuotePublic(_ token: String) -> String {
    if token.isEmpty { return "''" }
    let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "@%+=:,./-_"))
    if token.unicodeScalars.allSatisfy({ safe.contains($0) }) { return token }
    return "'" + token.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
}
