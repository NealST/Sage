//
//  mcp_tool_exposure.swift
//  CodexCore
//
//  Port of codex-rs/core/src/mcp_tool_exposure.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Live McpBinding / Apps policy waits. Session caches exposed catalog names.
//

import Foundation

public struct McpHandlerCache: Equatable, Sendable {
    public var exposedToolNames: [String]

    public init(exposedToolNames: [String] = []) {
        self.exposedToolNames = exposedToolNames
    }
}
