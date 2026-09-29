//
//  mcp_runner.swift
//  CodexHooks
//
//  Port of codex-rs/hooks/src/engine/mcp_runner.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  MCP tool execution is delegated to `HookMcpExecutor`. This file keeps
//  the runner entry point until engine execute_handlers is wired.
//

import CodexProtocol
import Foundation

public func runMcpTool(
    executor: any HookMcpExecutor,
    call: HookMcpCall
) async throws -> String {
    try await executor.execute(call)
}
