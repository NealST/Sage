//
//  permissions.swift
//  Sage
//
//  Port of codex-rs/core/src/guardian/permissions.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Resolves Guardian permission evidence from the host's captured environment
//  context. `ToolInvocation` / `TurnEnvironment` / permission-profile glob
//  expansion wait on Session, so `for_tool` and `for_environment` throw.
//

import CodexProtocol
import Foundation

/// Evidence collected for one Guardian review. Upstream type lives in
/// `codex_guardian_context::PermissionContext`.
struct GuardianPermissionContext: Equatable, Sendable {
    var environmentId: String?
    var deniedPaths: [String]
    var deniedGlobs: [String]
}

func toolPermissionContext() async throws -> GuardianPermissionContext {
    throw CodexErr.unsupportedOperation(
        "guardian/permissions.for_tool waits on ToolInvocation / TurnContext"
    )
}

func forEnvironment(
    context: GuardianReviewContext,
    environmentId: String?
) throws -> GuardianPermissionContext {
    _ = context
    _ = environmentId
    throw CodexErr.unsupportedOperation(
        "guardian/permissions.for_environment waits on TurnEnvironmentSnapshot"
    )
}
