//
//  service.swift
//  Sage
//
//  Port of codex-rs/core/src/state/service.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Phase 6/9 services (ModelClient, AuthManager, plugins) stay optional.
//  ExecutedToolCalls and unified exec are already in CodexCore / ToolsRuntimes.
//

import CodexCore
import CodexExecPolicy
import Foundation

final class SessionServices: @unchecked Sendable {
    var mcpRuntime: SessionMcpRuntime
    var execPolicy: Policy?
    var showRawAgentReasoning: Bool
    var selectedCapabilityRoots: [String]
    var executedToolCalls: ExecutedToolCalls
    var modelClient: CodexCore.ModelClient?

    init(
        mcpRuntime: SessionMcpRuntime = SessionMcpRuntime(),
        execPolicy: Policy? = nil,
        showRawAgentReasoning: Bool = false,
        selectedCapabilityRoots: [String] = [],
        modelClient: CodexCore.ModelClient? = nil
    ) {
        self.mcpRuntime = mcpRuntime
        self.execPolicy = execPolicy
        self.showRawAgentReasoning = showRawAgentReasoning
        self.selectedCapabilityRoots = selectedCapabilityRoots
        self.executedToolCalls = ExecutedToolCalls()
        self.modelClient = modelClient
    }
}
