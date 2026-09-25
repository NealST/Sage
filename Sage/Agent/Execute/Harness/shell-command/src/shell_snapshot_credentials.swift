//
//  shell_snapshot_credentials.swift
//  CodexShellCommand
//
//  Port of codex-rs/shell-command/src/shell_snapshot_credentials.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: partial
//
//  Credential-name heuristics used when redacting snapshot exports.
//

public func looksLikeCredentialName(_ name: String) -> Bool {
    let upper = name.uppercased()
    return ["TOKEN", "SECRET", "PASSWORD", "PASSWD", "API_KEY", "ACCESS_KEY", "PRIVATE_KEY"]
        .contains { upper.contains($0) }
}
