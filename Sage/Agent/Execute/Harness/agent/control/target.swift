//
//  target.swift
//  CodexCore
//
//  Port of codex-rs/core/src/agent/control/target.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  `ensure_agent_known` waits on ThreadManager. Direct IDs and path
//  references against the in-memory registry resolve without Session.
//

import CodexProtocol
import Foundation

extension LocalAgentControl {
    public func resolveTarget(caller: ThreadId, target: AgentTarget) throws -> ThreadId {
        switch target {
        case .id(let threadId):
            return threadId
        case .reference(let reference):
            let callerPath = runtime.registry.agentMetadataForThread(caller)?.agentPath
                ?? AgentPath.root()
            return try runtime.resolvePathReference(
                currentAgentPath: callerPath,
                agentReference: reference
            )
        }
    }
}
