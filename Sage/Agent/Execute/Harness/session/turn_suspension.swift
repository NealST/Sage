//
//  turn_suspension.swift
//  Sage
//
//  Port of codex-rs/core/src/session/turn_suspension.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import CodexProtocol
import Foundation

extension Session {
    func suspendActiveTurn() -> SuspendTurnOutcome {
        guard activeTurn != nil else { return .notActive }
        return .suspended(turnId: activeTurn?.task?.turnContext.subId ?? "")
    }
}
