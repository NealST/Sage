//
//  session_review.swift
//  Sage
//
//  Port of codex-rs/core/src/session/review.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import Foundation

extension Session {
    func isReviewTaskActive() -> Bool {
        activeTurn?.task?.kind == .review
    }
}
