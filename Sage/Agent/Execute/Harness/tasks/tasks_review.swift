//
//  tasks_review.swift
//  Sage
//
//  Port of codex-rs/core/src/tasks/review.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import CodexAsyncUtils
import CodexProtocol
import Foundation

final class ReviewTask: SessionTask, @unchecked Sendable {
    var kind: TaskKind { .review }

    init() {}

    func run(
        session: Session,
        context: TurnContext,
        input: [SessionTurnInput],
        cancellationToken: CancellationToken
    ) async throws -> String? {
        _ = input
        if cancellationToken.isCancelled {
            throw CodexErr(details: .turnAborted)
        }
        session.activeTurn = ActiveTurn(
            task: RunningTask(kind: .review, turnContext: context),
            turnState: TurnState()
        )
        await session.emitTurnStartLifecycle(context, tokenUsageAtTurnStart: nil, phase: .reviewTaskStart)
        await session.emitTurnStopLifecycle()
        return nil
    }
}
