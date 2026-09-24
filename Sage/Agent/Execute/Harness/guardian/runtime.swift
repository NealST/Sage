//
//  runtime.swift
//  Sage
//
//  Port of codex-rs/core/src/guardian/runtime.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: partial
//
//  `ReviewAction` mapping only; the full review runtime lands in Phase 8.
//

import Foundation

enum ReviewAction: Equatable, Sendable {
    case allow
    case deny(String)
    case ask(String)

    static func from(decision: ReviewDecision?) -> ReviewAction {
        switch decision {
        case .approved, .approvedForSession:
            return .allow
        case .denied(let reason):
            return .deny(reason)
        case .abort:
            return .deny("The review was aborted.")
        case nil:
            return .ask("A person must decide.")
        }
    }
}
