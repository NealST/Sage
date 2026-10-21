//
//  agent_resolver.swift
//  SageCore
//
//  Port of codex-rs/core/src/agent/agent_resolver.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Resolution closes over Session / TurnContext / AgentControl.
//

import SageProtocol
import Foundation

public func resolveAgentTarget(_ target: String) async throws -> ThreadId {
    throw SageErr.unsupportedOperation(
        "resolve_agent_target waits on Session / TurnContext / AgentControl"
    )
}

public func resolveAgentTargetError(_ error: SageErr) -> FunctionCallError {
    switch error.detailsValue() {
    case .unsupportedOperation(let message):
        return .respondToModel(message)
    default:
        return .respondToModel(error.description)
    }
}
