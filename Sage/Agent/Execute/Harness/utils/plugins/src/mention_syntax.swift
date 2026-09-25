//
//  mention_syntax.swift
//  CodexUtils
//
//  Port of codex-rs/utils/plugins/src/mention_syntax.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  Sigils for tool/plugin mentions in plaintext (shared across Codex crates).
//

/// Default plaintext sigil for tools.
public let toolMentionSigil: Character = "$"

/// Plugins use `@` in linked plaintext outside TUI.
public let pluginTextMentionSigil: Character = "@"
