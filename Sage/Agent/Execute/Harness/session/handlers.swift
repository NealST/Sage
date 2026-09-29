//
//  handlers.swift
//  Sage
//
//  Port of codex-rs/core/src/session/handlers.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  App-target Session dispatch remains a sampling stub. ThreadManager's
//  live submission loop is ThreadSession in session_mod.swift.
//

import Foundation

extension Session {
    func handle(_ submission: Submission) async {
        switch submission.op {
        case .interrupt, .shutdown:
            activeTurn?.task?.done = true
        case .userInput:
            break
        }
    }

    static func shutdownSessionRuntime(_ session: Session) async {
        session.state.shuttingDown = true
    }
}
