//
//  mod.swift
//  Sage
//
//  Port of codex-rs/core/src/guardian/mod.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Hosts approval decisions and the isolated synchronous reviewer.
//  `TurnContext` / `StepContext` / `ResolvedStepSettings` /
//  `TurnEnvironmentSnapshot` are not ported, so `GuardianReviewContext`
//  stores the review inputs that do not close over those types. From-turn
//  / from-step constructors throw until session types exist.
//

import CodexProtocol
import Foundation

let GUARDIAN_REVIEWER_NAME = "guardian"
let AUTO_REVIEW_DENIED_ACTION_APPROVAL_DEVELOPER_PREFIX =
    "The user has manually approved a specific action that was previously `Rejected`."
let GUARDIAN_MAX_ROOT_MESSAGE_TOKENS = 900
let GUARDIAN_MAX_NODE_REPL_TOOL_RESULT_TOKENS = 6_000

/// Captures review inputs from the issuing step without retaining its MCP bindings or tool router.
///
/// Background network approvals and Unix interception use the active task's resolved settings.
/// Startup reviewer prewarming intentionally uses turn-only inputs because it has no issuing step.
///
/// MCP elicitation reviews continue to use turn-only inputs.
struct GuardianReviewContext: Sendable {
    /// The latest response ID received in this turn when review was requested.
    var parentResponseId: String?
    var modelSlug: String
    var reasoningEffort: ReasoningEffort?
    var reasoningSummary: ReasoningSummary
    var personality: Personality?
    var approvalPolicy: AskForApproval
    var approvalsReviewer: ApprovalsReviewer

    func modelContext() -> ModelInvocationContext {
        ModelInvocationContext(
            modelSlug: modelSlug,
            reasoningEffort: reasoningEffort?.asStr
        )
    }
}
