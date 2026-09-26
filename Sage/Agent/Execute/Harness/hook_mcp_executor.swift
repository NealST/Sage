//
//  hook_mcp_executor.swift
//  CodexCore
//
//  Port of codex-rs/core/src/hook_mcp_executor.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  `McpRuntime.latest_call_tool` is not ported. `CoreHookMcpExecutor`
//  records the thread id and throws until MCP runtime exists.
//

import CodexHooks
import CodexProtocol
import Foundation

public struct CoreHookMcpExecutor: HookMcpExecutor, Sendable {
    public var threadId: ThreadId

    public init(threadId: ThreadId) {
        self.threadId = threadId
    }

    public func execute(_ call: HookMcpCall) async throws -> String {
        _ = call
        throw CodexErr.unsupportedOperation(
            "CoreHookMcpExecutor.execute waits on McpRuntime"
        )
    }
}
