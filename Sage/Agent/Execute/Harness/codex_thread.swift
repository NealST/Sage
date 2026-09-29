//
//  codex_thread.swift
//  CodexCore
//
//  Port of codex-rs/core/src/codex_thread.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Session, Op submission, and store persistence are not wired. This is the
//  public handle type plus startup metadata.
//

import CodexProtocol
import Foundation

/// Snapshot of a live thread's effective settings. Config-owned fields stay
/// optional until the Config crate is ported.
public struct ThreadConfigSnapshot: Equatable {
    public var model: String
    public var modelProviderId: String
    public var serviceTier: String?
    public var approvalPolicy: AskForApproval
    public var fullAccess: Bool
    public var ephemeral: Bool
    public var sessionSource: SessionSource
    public var historyMode: ThreadHistoryMode
    public var forkedFromThreadId: ThreadId?
    public var parentThreadId: ThreadId?
    public var threadSource: ThreadSource?
    public var originator: String
    public var disabledPluginIds: [String]
    public var environments: TurnEnvironmentSelections?

    public init(
        model: String,
        modelProviderId: String = "",
        serviceTier: String? = nil,
        approvalPolicy: AskForApproval = .onRequest,
        fullAccess: Bool = false,
        ephemeral: Bool = false,
        sessionSource: SessionSource = .unknown,
        historyMode: ThreadHistoryMode = .legacy,
        forkedFromThreadId: ThreadId? = nil,
        parentThreadId: ThreadId? = nil,
        threadSource: ThreadSource? = nil,
        originator: String = "",
        disabledPluginIds: [String] = [],
        environments: TurnEnvironmentSelections? = nil
    ) {
        self.model = model
        self.modelProviderId = modelProviderId
        self.serviceTier = serviceTier
        self.approvalPolicy = approvalPolicy
        self.fullAccess = fullAccess
        self.ephemeral = ephemeral
        self.sessionSource = sessionSource
        self.historyMode = historyMode
        self.forkedFromThreadId = forkedFromThreadId
        self.parentThreadId = parentThreadId
        self.threadSource = threadSource
        self.originator = originator
        self.disabledPluginIds = disabledPluginIds
        self.environments = environments
    }

    public func environmentSelections() -> [TurnEnvironmentSelection] {
        environments?.environments ?? []
    }

    public func isPrimaryEnvironmentConfigured() -> Bool {
        guard let selection = environmentSelections().first else { return true }
        switch selection.config {
        case .fromThread, .ready:
            return true
        case .pending, .failed:
            return false
        }
    }
}

public struct GuardianAuthorizationVersion: Equatable, Sendable {
    public var userMessageRevision: UInt64
    public var retainedContextComplete: Bool

    public init(userMessageRevision: UInt64, retainedContextComplete: Bool) {
        self.userMessageRevision = userMessageRevision
        self.retainedContextComplete = retainedContextComplete
    }
}

/// Bounded root conversation and authorization state from one history snapshot.
public struct GuardianRootSnapshot: Equatable, Sendable {
    public var rootThreadId: ThreadId
    public var authorizationVersion: GuardianAuthorizationVersion
    public var trustedSkillPaths: [String]

    public init(
        rootThreadId: ThreadId,
        authorizationVersion: GuardianAuthorizationVersion,
        trustedSkillPaths: [String] = []
    ) {
        self.rootThreadId = rootThreadId
        self.authorizationVersion = authorizationVersion
        self.trustedSkillPaths = trustedSkillPaths
    }
}

public final class CodexThread: @unchecked Sendable {
    public let threadId: ThreadId
    public let startup: ThreadStartupMetadata

    public init(threadId: ThreadId, startup: ThreadStartupMetadata) {
        self.threadId = threadId
        self.startup = startup
    }
}
