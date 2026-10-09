//
//  request_permissions_response.swift
//  Sage
//
//  Port of `request_permissions` / `notify_request_permissions_response` in
//  codex-rs/core/src/session/mod.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  A `request_permissions` call checks the turn approval policy, then a
//  guardian decision, before it waits on the user. `Never` and a granular
//  policy that disallows the tool return an empty turn grant and do not
//  emit a request. A guardian decision is normalized and recorded the same
//  way as a user grant, with `strict_auto_review` false, and also does not
//  emit a request. Normalization uses the environment policy context,
//  including workspace roots and temporary directories. No decision falls
//  through to the user waiter, keyed by
//  tool call id. `Op::RequestPermissionsResponse` intersects the user's
//  grant with the request, records a turn-scoped grant on that turn and a
//  session-scoped grant on the session, then resumes the waiter. It does
//  not start a turn. A missing waiter is ignored. Cancelling the token
//  removes that call's waiter.
//

import CodexAsyncUtils
import CodexProtocol
import CodexSandboxing
import CodexUtils
import Foundation

extension Session {
    /// rust `Session::request_permissions_for_environment`, after the tool
    /// has resolved the environment and its paths.
    func requestPermissions(
        turnContext: TurnContext,
        callId: String,
        args: RequestPermissionsArgs,
        policyContext: FileSystemSandboxPolicyContext? = nil,
        cancellationToken: CancellationToken
    ) async -> RequestPermissionsResponse? {
        let environmentId = args.environmentId ?? turnContext.environment.environmentId
        if requestPermissionsBlocked(by: turnContext.approvalPolicy) {
            return RequestPermissionsResponse(
                permissions: RequestPermissionProfile(),
                scope: .turn,
                strictAutoReview: false
            )
        }
        if cancellationToken.isCancelled {
            return nil
        }
        if let guardian = requestPermissionsGuardian {
            let decision = await guardian(args)
            if cancellationToken.isCancelled {
                return nil
            }
            if let decision {
                return applyGuardianRequestPermissionsDecision(
                    decision,
                    requested: args.permissions,
                    environmentId: environmentId,
                    policyContext: policyContext ?? sandboxPolicyContext(cwd: turnContext.cwd)
                )
            }
        }
        let requestId = UUID()
        return await withCheckedContinuation { continuation in
            if cancellationToken.isCancelled {
                continuation.resume(returning: nil)
            } else if let turn = activeTurn {
                let decision = PermissionsDecision(continuation)
                let previous = turn.turnState.insertPendingRequestPermissions(
                    key: callId,
                    pending: PendingRequestPermissions(
                        requestId: requestId,
                        requestedPermissions: args.permissions,
                        environmentId: environmentId,
                        policyContext: policyContext,
                        decision: decision
                    )
                )
                previous?.decision.resume(nil)
                let token = cancellationToken
                Task {
                    await token.waitForCancellation()
                    guard let current = turn.turnState.pendingRequestPermissions[callId],
                          current.requestId == requestId
                    else { return }
                    turn.turnState.pendingRequestPermissions.removeValue(forKey: callId)
                    current.decision.resume(nil)
                }
            } else {
                continuation.resume(returning: nil)
            }
            sendEvent(
                turnContext,
                .requestPermissions(
                    RequestPermissionsEvent(
                        callId: callId,
                        turnId: turnContext.subId,
                        environmentId: environmentId,
                        startedAtMs: Int64(Date().timeIntervalSince1970 * 1000),
                        reason: args.reason,
                        permissions: args.permissions,
                        cwd: LegacyAppPathString.fromString(turnContext.cwd)
                    )
                )
            )
        }
    }

    /// rust `Session::notify_request_permissions_response`.
    func notifyRequestPermissionsResponse(id: String, response: RequestPermissionsResponse) {
        guard let turn = activeTurn,
              let pending = turn.turnState.removePendingRequestPermissions(key: id)
        else { return }
        let normalized = normalizeRequestPermissionsResponse(
            requested: pending.requestedPermissions,
            response: response,
            context: pending.policyContext
                ?? sandboxPolicyContext(cwd: turn.task?.turnContext.cwd ?? "")
        )
        recordGrantedRequestPermissions(
            response: normalized,
            environmentId: pending.environmentId,
            turnState: turn.turnState
        )
        pending.decision.resume(normalized)
    }

    private func applyGuardianRequestPermissionsDecision(
        _ decision: CodexProtocol.ReviewDecision,
        requested: RequestPermissionProfile,
        environmentId: String,
        policyContext: FileSystemSandboxPolicyContext?
    ) -> RequestPermissionsResponse {
        let mapped = mapGuardianRequestPermissionsDecision(decision, requested: requested)
        let normalized = normalizeRequestPermissionsResponse(
            requested: requested,
            response: mapped,
            context: policyContext
        )
        if let turn = activeTurn {
            recordGrantedRequestPermissions(
                response: normalized,
                environmentId: environmentId,
                turnState: turn.turnState
            )
        } else if normalized.scope == .session, !normalized.permissions.isEmpty {
            state.recordGrantedPermissions(
                environmentId: environmentId,
                permissions: AdditionalPermissionProfile(normalized.permissions)
            )
        }
        return normalized
    }

    private func recordGrantedRequestPermissions(
        response: RequestPermissionsResponse,
        environmentId: String,
        turnState: TurnState
    ) {
        if response.permissions.isEmpty { return }
        let permissions = AdditionalPermissionProfile(response.permissions)
        switch response.scope {
        case .turn:
            turnState.recordGrantedPermissions(
                environmentId: environmentId, permissions: permissions)
            if response.strictAutoReview {
                turnState.enableStrictAutoReview()
            }
        case .session:
            state.recordGrantedPermissions(
                environmentId: environmentId, permissions: permissions)
        }
    }
}

private func requestPermissionsBlocked(by policy: CodexProtocol.AskForApproval) -> Bool {
    switch policy {
    case .never:
        return true
    case .granular(let config):
        return !config.allowsRequestPermissions()
    case .onRequest, .unlessTrusted:
        return false
    }
}

/// rust `request_permissions_for_environment` decision match.
/// Approved, an execpolicy amendment, and a network allow keep the request
/// for this turn. Approved-for-session keeps it for the session. Every
/// other decision grants nothing. `strict_auto_review` stays false.
private func mapGuardianRequestPermissionsDecision(
    _ decision: CodexProtocol.ReviewDecision,
    requested: RequestPermissionProfile
) -> RequestPermissionsResponse {
    let permissions: RequestPermissionProfile
    let scope: PermissionGrantScope
    switch decision {
    case .approved, .approvedExecpolicyAmendment:
        permissions = requested
        scope = .turn
    case .approvedForSession:
        permissions = requested
        scope = .session
    case .networkPolicyAmendment(let amendment):
        switch amendment.action {
        case .allow:
            permissions = requested
            scope = .turn
        case .deny:
            permissions = RequestPermissionProfile()
            scope = .turn
        }
    case .approvedMcpPolicyAmendment, .abort, .denied, .timedOut:
        permissions = RequestPermissionProfile()
        scope = .turn
    }
    return RequestPermissionsResponse(
        permissions: permissions,
        scope: scope,
        strictAutoReview: false
    )
}

private func normalizeRequestPermissionsResponse(
    requested: RequestPermissionProfile,
    response: RequestPermissionsResponse,
    context: FileSystemSandboxPolicyContext?
) -> RequestPermissionsResponse {
    if response.strictAutoReview && response.scope == .session {
        return RequestPermissionsResponse(
            permissions: RequestPermissionProfile(),
            scope: .turn,
            strictAutoReview: false
        )
    }
    if response.permissions.isEmpty { return response }
    guard let context else { return response }
    let intersected = intersectPermissionProfilesWithContext(
        requested: AdditionalPermissionProfile(requested),
        granted: AdditionalPermissionProfile(response.permissions),
        context: context
    )
    return RequestPermissionsResponse(
        permissions: RequestPermissionProfile(intersected),
        scope: response.scope,
        strictAutoReview: response.strictAutoReview
    )
}

private func sandboxPolicyContext(cwd: String) -> FileSystemSandboxPolicyContext? {
    let path = (try? AbsolutePathBuf.fromAbsolutePath(cwd))
        ?? (try? AbsolutePathBuf.fromAbsolutePath("/"))
    guard let path else { return nil }
    let uri = PathUri(path)
    return FileSystemSandboxPolicyContext(cwd: uri, workspaceRoots: [uri])
}
