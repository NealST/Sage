//
//  response_adapter.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/code_mode/response_adapter.rs
//  (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Protocol content items are already the host type. This keeps the
//  mapping entry point for when code_mode crate types land.
//

import CodexProtocol

func intoFunctionCallOutputContentItems(
    _ items: [FunctionCallOutputContentItem]
) -> [FunctionCallOutputContentItem] {
    items
}
