//
//  thread_startup_metadata.swift
//  CodexCore
//
//  Port of codex-rs/core/src/thread_startup_metadata.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import CodexProtocol
import CodexUtils
import Foundation

/// The configuration reported when a thread started, without its replay history.
public struct ThreadStartupMetadata: Sendable {
    public var sessionId: SessionId
    public var threadId: ThreadId
    var forkedFromId: ThreadId?
    var parentThreadId: ThreadId?
    var threadSource: ThreadSource?
    var threadName: String?
    var model: String
    var modelProviderId: String
    var serviceTier: String?
    var approvalPolicy: AskForApproval
    var approvalsReviewer: ApprovalsReviewer
    var permissionProfile: PermissionProfile
    var activePermissionProfile: ActivePermissionProfile?
    var cwd: AbsolutePathBuf
    var reasoningEffort: ReasoningEffort?
    var networkProxy: SessionNetworkProxyRuntime?
    var rolloutPath: String?

    public init(from event: SessionConfiguredEvent) {
        sessionId = event.sessionId
        threadId = event.threadId
        forkedFromId = event.forkedFromId
        parentThreadId = event.parentThreadId
        threadSource = event.threadSource
        threadName = event.threadName
        model = event.model
        modelProviderId = event.modelProviderId
        serviceTier = event.serviceTier
        approvalPolicy = event.approvalPolicy
        approvalsReviewer = event.approvalsReviewer
        permissionProfile = event.permissionProfile
        activePermissionProfile = event.activePermissionProfile
        cwd = event.cwd
        reasoningEffort = event.reasoningEffort
        networkProxy = event.networkProxy
        rolloutPath = event.rolloutPath
    }

    public func toSessionConfiguredEvent(initialMessages: [EventMsg]?) -> SessionConfiguredEvent {
        var event = SessionConfiguredEvent(
            sessionId: sessionId,
            threadId: threadId,
            model: model,
            modelProviderId: modelProviderId,
            approvalPolicy: approvalPolicy,
            permissionProfile: permissionProfile,
            cwd: cwd
        )
        event.forkedFromId = forkedFromId
        event.parentThreadId = parentThreadId
        event.threadSource = threadSource
        event.threadName = threadName
        event.serviceTier = serviceTier
        event.approvalsReviewer = approvalsReviewer
        event.activePermissionProfile = activePermissionProfile
        event.reasoningEffort = reasoningEffort
        event.initialMessages = initialMessages
        event.networkProxy = networkProxy
        event.rolloutPath = rolloutPath
        return event
    }
}
