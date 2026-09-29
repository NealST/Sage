//
//  runtime_context.swift
//  CodexCore
//
//  Port of codex-rs/core/src/agent/control/runtime_context.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  `register_session_root` / `ensure_agent_known` live on LocalAgentRuntime
//  in control.swift. Descendant listing waits on ThreadManager.
//

import CodexProtocol
import Foundation

extension LocalAgentRuntime {
    public func listLiveAgentSubtreeThreadIds(_ agentId: ThreadId) async throws -> [ThreadId] {
        throw CodexErr.unsupportedOperation(
            "list_live_agent_subtree_thread_ids waits on ThreadManager"
        )
    }

    public func formatLegacyEnvironmentContextSubagents() async throws -> String {
        throw CodexErr.unsupportedOperation(
            "format_legacy_environment_context_subagents waits on ThreadManager"
        )
    }
}
