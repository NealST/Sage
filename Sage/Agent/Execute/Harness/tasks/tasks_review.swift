//
//  tasks_review.swift
//  Sage
//
//  Port of codex-rs/core/src/tasks/review.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  The parent turn samples the resolved review prompt via `runTurn`.
//  A dedicated child thread, review rubric instructions, and the
//  exit-message templates wait. Entered/exited review items still
//  bookend the sample, and the last assistant text is parsed as
//  `ReviewOutputEvent` when it is JSON.
//

import CodexAsyncUtils
import CodexProtocol
import Foundation

final class ReviewTask: SessionTask, @unchecked Sendable {
    var kind: TaskKind { .review }
    let resolved: ResolvedReviewRequest

    init(resolved: ResolvedReviewRequest) {
        self.resolved = resolved
    }

    func run(
        session: Session,
        context: TurnContext,
        input: [SessionTurnInput],
        cancellationToken: CancellationToken
    ) async throws -> String? {
        if cancellationToken.isCancelled {
            throw CodexErr(details: .turnAborted)
        }
        if session.activeTurn == nil {
            session.activeTurn = ActiveTurn(
                task: RunningTask(kind: .review, turnContext: context),
                turnState: TurnState()
            )
        } else if session.activeTurn?.task == nil {
            session.activeTurn?.task = RunningTask(kind: .review, turnContext: context)
        }
        await session.emitTurnStartLifecycle(
            context,
            tokenUsageAtTurnStart: nil,
            phase: .reviewTaskStart
        )
        let entered = TurnItem.enteredReviewMode(
            EnteredReviewModeItem(
                id: UUID().uuidString,
                target: resolved.target,
                userFacingHint: resolved.userFacingHint
            )
        )
        session.emitTurnItemStarted(context, entered)
        session.emitTurnItemCompleted(context, entered)

        var reviewInput = input
        var requirements = McpStartupRequirements()
        let message: String?
        do {
            message = try await runTurn(
                sess: session,
                turnContext: context,
                input: &reviewInput,
                mcpStartupRequirements: &requirements,
                prewarmedClientSession: nil,
                cancellationToken: cancellationToken.childToken()
            )
        } catch {
            if cancellationToken.isCancelled {
                throw CodexErr(details: .turnAborted)
            }
            emitExitedReviewMode(session: session, context: context, output: nil)
            throw error
        }
        if cancellationToken.isCancelled {
            throw CodexErr(details: .turnAborted)
        }
        let output = message.map(parseReviewOutputEvent)
        emitExitedReviewMode(session: session, context: context, output: output)
        return message
    }

    private func emitExitedReviewMode(
        session: Session,
        context: TurnContext,
        output: ReviewOutputEvent?
    ) {
        let exited = TurnItem.exitedReviewMode(
            ExitedReviewModeItem(id: UUID().uuidString, reviewOutput: output)
        )
        session.emitTurnItemStarted(context, exited)
        session.emitTurnItemCompleted(context, exited)
    }
}

func parseReviewOutputEvent(_ text: String) -> ReviewOutputEvent {
    if let event = decodeReviewOutput(text) {
        return event
    }
    if let start = text.firstIndex(of: "{"),
       let end = text.lastIndex(of: "}"),
       start < end,
       let event = decodeReviewOutput(String(text[start...end]))
    {
        return event
    }
    return ReviewOutputEvent(overallExplanation: text)
}

private func decodeReviewOutput(_ text: String) -> ReviewOutputEvent? {
    guard let data = text.data(using: .utf8) else { return nil }
    return try? JSONDecoder().decode(ReviewOutputEvent.self, from: data)
}
