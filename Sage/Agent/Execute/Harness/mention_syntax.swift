//
//  mention_syntax.swift
//  CodexCore
//
//  Port of codex-rs/core/src/mention_syntax.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  Re-exports the utils/plugins sigils under the Rust constant names.
//

import CodexUtils

public let TOOL_MENTION_SIGIL = CodexUtils.toolMentionSigil
public let PLUGIN_TEXT_MENTION_SIGIL = CodexUtils.pluginTextMentionSigil
