//
//  submission.swift
//  Sage
//
//  Port of codex-rs/core/src/session/submission.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import CodexProtocol
import Foundation

enum SessionOp: Equatable, Sendable {
    case interrupt
    case shutdown
    case userInput(TurnInput)
}

struct Submission: Sendable {
    var id: String
    var op: SessionOp
    var parentTurnId: String?
    var rootTurnId: String?

    init(id: String, op: SessionOp, parentTurnId: String? = nil, rootTurnId: String? = nil) {
        self.id = id
        self.op = op
        self.parentTurnId = parentTurnId
        self.rootTurnId = rootTurnId
    }
}
