//
//  mcp.swift
//  CodexHooks
//
//  Port of codex-rs/hooks/src/mcp.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  Boxed futures become an async protocol method. `serde_json::Map` is
//  `[String: JSONValue]`. `Duration` is `TimeInterval`.
//

import CodexProtocol
import Foundation

/// One MCP tool call requested by a configured hook handler.
public struct HookMcpCall: Equatable, Sendable {
    public var server: String
    public var tool: String
    public var environmentId: String?
    public var metadata: [String: JSONValue]?
    public var input: [String: JSONValue]
    public var timeout: TimeInterval

    public init(
        server: String,
        tool: String,
        environmentId: String? = nil,
        metadata: [String: JSONValue]? = nil,
        input: [String: JSONValue] = [:],
        timeout: TimeInterval
    ) {
        self.server = server
        self.tool = tool
        self.environmentId = environmentId
        self.metadata = metadata
        self.input = input
        self.timeout = timeout
    }
}

/// Executes already-connected MCP tools on behalf of hooks without coupling this crate to core.
///
/// Implementations own server readiness, policy enforcement, timeout handling, and elicitation.
public protocol HookMcpExecutor: Sendable {
    /// Returns text that is interpreted using ordinary command-hook output semantics.
    func execute(_ call: HookMcpCall) async throws -> String
}
