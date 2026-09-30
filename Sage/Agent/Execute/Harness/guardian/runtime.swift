//
//  runtime.swift
//  Sage
//
//  Port of codex-rs/core/src/guardian/runtime.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Captures one HUD approval for the isolated reviewer. Session spawn,
//  history-reset cancel, and extension host stay out.
//

import Foundation

enum ReviewValidation: Equatable, Sendable {
    case ready(GuardianApprovalRequest)
    case denied(ReviewDecision)
}

/// Codex `ReviewAction`: the prepared request plus its Guardian scope.
struct ReviewAction: Equatable, Sendable {
    var request: GuardianApprovalRequest?
    var prepareError: String?
    var scope: GuardianScope

    static func from(_ request: GuardianApprovalRequest) -> ReviewAction {
        ReviewAction(request: request, prepareError: nil, scope: request.scope)
    }

    static func from(_ action: ApprovalAction) -> ReviewAction {
        from(GuardianApprovalRequest.from(action))
    }

    static func unprepared(scope: GuardianScope, error: String) -> ReviewAction {
        ReviewAction(request: nil, prepareError: error, scope: scope)
    }

    /// Codex `ReviewAction::validate`. Turn environments stay out; a
    /// `write_stdin` with no process still cannot be reviewed automatically.
    func validate() -> ReviewValidation {
        guard let request else {
            return .denied(
                .denied(reason: "automatic approval review could not prepare the action")
            )
        }
        if case .writeStdin(_, let processID, let input, _) = request {
            if processID <= 0 {
                return .denied(
                    .denied(
                        reason: "automatic approval review cannot access the terminal's environment; select it before retrying"
                    )
                )
            }
            if input.contains("\0") {
                return .denied(
                    .denied(
                        reason: "terminal input contains a NUL byte and cannot be reviewed safely"
                    )
                )
            }
        }
        return .ready(request)
    }

    func pretty() -> String {
        request?.pretty() ?? prepareError ?? "unprepared action"
    }
}

/// Isolated review for one HUD action. `nil` still falls through to the card.
struct ReviewRuntime: Sendable {
    var request: ReviewAction
    var reasons: ApprovalRequestReasons
    var options: GuardianReviewOptions

    @MainActor
    func decide(events: [AgentEvent] = []) async -> ReviewDecision? {
        let preparedRequest: GuardianApprovalRequest
        switch request.validate() {
        case .ready(let request):
            preparedRequest = request
        case .denied(let decision):
            return decision
        }
        let config = GuardianReviewerConfig.resolveLive(scope: preparedRequest.scope)
        let prepared = PreparedGuardianContext.prepare(
            request: preparedRequest,
            approvalReason: reasons.approval,
            retryReason: reasons.retry,
            events: events,
            config: config
        )
        let usable = PromptBudget.forModel(config.model).usableTokens
        if GuardianRequestBudget.check(
            prompt: prepared.user,
            instructions: prepared.system,
            usableTokens: usable
        ) != nil {
            return .denied(reason: "Guardian review input exceeds the context window.")
        }
        do {
            let raw = try await GuardianReviewSession.shared.review(
                prompt: prepared.user,
                config: config
            )
            if let parsed = GuardianPrompt.parse(raw) {
                return parsed
            }
            if GuardianPrompt.isAsk(raw) {
                return nil
            }
            if options.requireGuardian {
                return .denied(reason: "Guardian could not review this action.")
            }
            return nil
        } catch {
            _ = GuardianFeedback.record(
                reviewID: prepared.reviewID,
                action: request.pretty(),
                error: error
            )
            return nil
        }
    }
}
