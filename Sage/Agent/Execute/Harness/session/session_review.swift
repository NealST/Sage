//
//  session_review.swift
//  Sage
//
//  Port of codex-rs/core/src/session/review.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  A review submission resolves the prompt, disables web search and
//  goals on the review turn, and starts `ReviewTask`. The child
//  one-shot thread is not spawned; `ReviewTask` samples the prompt
//  on this session. Model-catalog refresh and reasoning-effort
//  retargeting wait.
//

import CodexProtocol
import Foundation

extension Session {
    func isReviewTaskActive() -> Bool {
        activeTurn?.task?.kind == .review
    }

    /// rust `handlers::review` then `spawn_review_thread`.
    func startReview(submissionId: String, request: ReviewRequest) async {
        if state.shuttingDown { return }
        let turn = newTurnContext(subId: submissionId)
        if let reviewModel = turn.config.reviewModel, !reviewModel.isEmpty {
            turn.model = reviewModel
            turn.nextStepSettings.model = reviewModel
            turn.nextStepSettings.modelSnapshot.slug = reviewModel
        }
        turn.config.features.disable(.webSearchRequest)
        turn.config.features.disable(.webSearchCached)
        turn.config.features.disable(.goals)
        let resolved: ResolvedReviewRequest
        do {
            resolved = try resolveReviewRequest(request, cwd: turn.cwd)
        } catch {
            sendEvent(turn, .error(ErrorEvent(message: String(describing: error))))
            return
        }
        if hasRunningTask {
            await abortAllTasks(reason: .replaced)
        }
        lastStartedTurnContext = turn
        lastStartedTurnId = turn.subId
        startDetachedTask(
            ReviewTask(resolved: resolved),
            turnContext: turn,
            input: [TurnInputBuilder.user([.text(text: resolved.prompt, textElements: [])])]
        )
    }
}
