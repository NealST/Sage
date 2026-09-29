//
//  status.swift
//  CodexCore
//
//  Port of codex-rs/core/src/agent/status.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  `TurnCompleteEvent` does not yet carry `error` / `last_agent_message`.
//  Interrupted completions map to `.interrupted`; other completions map to
//  `.completed(nil)`. `TurnAborted` and `ShutdownComplete` are not on
//  `EventMsg` yet.
//

import CodexProtocol
import Foundation

/// Derive the next agent status from a single emitted event.
/// Returns `nil` when the event does not affect status tracking.
public func agentStatusFromEvent(_ msg: EventMsg) -> AgentStatus? {
    switch msg {
    case .turnStarted:
        return .running
    case .turnComplete(let event):
        if event.interrupted {
            return .interrupted
        }
        return .completed(nil)
    case .error(let event):
        return .errored(event.message)
    default:
        return nil
    }
}

public func isFinal(_ status: AgentStatus) -> Bool {
    switch status {
    case .pendingInit, .running, .interrupted:
        return false
    default:
        return true
    }
}
