//
//  submission.swift
//  Sage
//
//  Port of codex-rs/core/src/session/submission.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  SessionOp is the subset the app-target Session loop dispatches.
//  Realtime / elicitation / approval replies stay on ThreadSession.
//

import CodexProtocol
import Foundation

enum SessionOp: Equatable, Sendable {
    case interrupt
    case shutdown
    case userInput(SessionTurnInput)
    case interAgent(InterAgentCommunication)
    case compact
}

final class SubmissionAck: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?
    private var fired = false

    func signal() {
        lock.lock()
        fired = true
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume()
    }

    func wait() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            if fired {
                lock.unlock()
                continuation.resume()
                return
            }
            self.continuation = continuation
            lock.unlock()
        }
    }
}

struct Submission: Sendable {
    var id: String
    var op: SessionOp
    var parentTurnId: String?
    var rootTurnId: String?
    var ack: SubmissionAck?

    init(
        id: String,
        op: SessionOp,
        parentTurnId: String? = nil,
        rootTurnId: String? = nil,
        ack: SubmissionAck? = nil
    ) {
        self.id = id
        self.op = op
        self.parentTurnId = parentTurnId
        self.rootTurnId = rootTurnId
        self.ack = ack
    }
}
