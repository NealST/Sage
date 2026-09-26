//
//  session_mcp.swift
//  Sage
//
//  Port of codex-rs/core/src/session/mcp.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Transport stays on Sage MCPStdioClient. This file keeps the session
//  binding surface so Phase 4 handlers can call through later.
//

import Foundation

extension Session {
    func ensureMcpConnected() async {}

    func listMcpTools() -> [String] {
        []
    }
}
