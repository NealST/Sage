//
//  tasks_review.swift
//  Sage
//
//  Port of codex-rs/core/src/tasks/review.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import Foundation

final class ReviewTask: SessionTask, @unchecked Sendable {
    var kind: TaskKind { .review }

    init() {}

    func run(session: Session, context: TurnContext) async throws -> String? {
        session.activeTurn = ActiveTurn(
            task: RunningTask(kind: .review, turnContext: context),
            turnState: TurnState()
        )
        await session.emitTurnStartLifecycle(context, tokenUsageAtTurnStart: nil, phase: .reviewTaskStart)
        await session.emitTurnStopLifecycle()
        return nil
    }
}
