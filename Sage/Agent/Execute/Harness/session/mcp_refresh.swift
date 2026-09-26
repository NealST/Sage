//
//  mcp_refresh.swift
//  Sage
//
//  Port of codex-rs/core/src/session/mcp_refresh.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import Foundation

final class McpRefresh: @unchecked Sendable {
    var dirty = false

    init() {}

    func markDirty() { dirty = true }
}
