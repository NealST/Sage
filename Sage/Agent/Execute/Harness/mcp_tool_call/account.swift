//
//  account.swift
//  CodexCore
//
//  Port of codex-rs/core/src/mcp_tool_call/account.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import Foundation

public struct McpToolCallAccount: Equatable, Sendable {
    public var accountId: String?

    public init(accountId: String? = nil) {
        self.accountId = accountId
    }
}
