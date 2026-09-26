//
//  daemon_recovery.swift
//  Sage
//
//  Port of codex-rs/core/src/session/daemon_recovery.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import CodexProtocol
import Foundation

struct RecordedTurnInput {}

extension Session {
    func interruptedTurn() -> (String, TurnStartOptions, String)? {
        guard let task = activeTurn?.task, task.kind == .regular else { return nil }
        return (task.turnContext.subId, TurnStartOptions(), task.turnContext.environment.environmentId)
    }
}
