//
//  codex_thread.swift
//  CodexCore
//
//  Port of codex-rs/core/src/codex_thread.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Each live handle owns a ThreadSession submission loop. The handle also
//  carries sessionSource, a config snapshot, a shutdown latch, a recorded
//  submission/event log, in-memory history items, and an AgentStatus watch.
//

import CodexHistory
import CodexProtocol
import Foundation
import os

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

/// Session-free subset of rust `Op` that live registry submission can record.
public enum ThreadOp: Equatable, Sendable {
    case interrupt
    case shutdown
    case interAgentCommunication(InterAgentCommunication, startOptions: TurnStartOptions)
}

public final class CodexThread: @unchecked Sendable {
    public let threadId: ThreadId
    public let startup: ThreadStartupMetadata
    public let sessionSource: SessionSource
    private let snapshot: ThreadConfigSnapshot
    private struct RuntimeState: Sendable {
        var shutdown = false
        var session: ThreadSession?
        var submissions: [(String, ThreadOp)] = []
        var events: [Event] = []
        var history: [RolloutItem] = []
        var agentStatus: AgentStatus = .pendingInit
    }

    private let runtimeLock = OSAllocatedUnfairLock(initialState: RuntimeState())
    private let waitersLock = NSLock()
    private var statusWaiters: [UUID: AsyncStream<AgentStatus>.Continuation] = [:]

    public init(
        threadId: ThreadId,
        startup: ThreadStartupMetadata,
        sessionSource: SessionSource = .unknown,
        configSnapshot: ThreadConfigSnapshot? = nil
    ) {
        self.threadId = threadId
        self.startup = startup
        self.sessionSource = sessionSource
        snapshot = configSnapshot ?? ThreadConfigSnapshot(
            model: startup.model,
            modelProviderId: startup.modelProviderId,
            serviceTier: startup.serviceTier,
            approvalPolicy: startup.approvalPolicy,
            sessionSource: sessionSource,
            parentThreadId: startup.parentThreadId ?? sessionSource.parentThreadId(),
            threadSource: startup.threadSource
        )
    }

    public func configSnapshot() -> ThreadConfigSnapshot {
        snapshot
    }

    public func isRunning() -> Bool {
        !runtimeLock.withLock { $0.shutdown }
    }

    public func liveSession() -> ThreadSession? {
        runtimeLock.withLock { $0.session }
    }

    func openLiveSession(
        sampler: (any TurnSampler)? = nil,
        toolRunner: (any TurnToolRunner)? = nil
    ) {
        if runtimeLock.withLock({ $0.session }) != nil {
            return
        }
        let session = ThreadSession.open(
            threadId: threadId,
            sessionSource: sessionSource,
            sampler: sampler,
            toolRunner: toolRunner
        ) { [weak self] event in
            self?.recordEvent(event)
        }
        runtimeLock.withLock { state in
            if state.session == nil {
                state.session = session
            }
        }
    }

    func submitSpawnInput(_ input: AgentInput, options: SpawnAgentOptions) async throws {
        guard let session = liveSession() else {
            throw CodexErr.internalAgentDied
        }
        switch input {
        case .userInput(let items):
            let submission = try await session.submitTurnInput(
                TurnInputRequest.userInput(items).onStart(
                    TurnStartOptions(
                        turnTrigger: options.turnTrigger,
                        parentTurnId: options.parentTurnId,
                        rootTurnId: options.rootTurnId,
                        cyberAccessProgram: options.cyberAccessProgram
                    )
                ),
                mode: .startOrSteer
            )
            if case .notSubmitted(let reason) = submission {
                throw CodexErr.invalidRequest("spawn turn input was not submitted (\(reason))")
            }
        case .message:
            return
        }
    }

    /// Closes the submission loop, then the live-registry shutdown latch.
    public func shutdownAndWait() async throws {
        let session = runtimeLock.withLock { state -> ThreadSession? in
            state.shutdown = true
            return state.session
        }
        await session?.shutdown()
    }

    public func submit(_ op: ThreadOp) -> String {
        let submissionId = UUID().uuidString.lowercased()
        runtimeLock.withLock { state in
            state.submissions.append((submissionId, op))
            if case .shutdown = op {
                state.shutdown = true
            }
        }
        return submissionId
    }

    public func recordEvent(_ event: Event) {
        runtimeLock.withLock { $0.events.append(event) }
    }

    public func recordedEvents() -> [Event] {
        runtimeLock.withLock { $0.events }
    }

    public func submittedOps() -> [ThreadOp] {
        runtimeLock.withLock { $0.submissions.map(\.1) }
    }

    public func historyItems() -> [RolloutItem] {
        runtimeLock.withLock { $0.history }
    }

    public func replaceHistory(_ items: [RolloutItem]) {
        runtimeLock.withLock { $0.history = items }
    }

    public func agentStatus() -> AgentStatus {
        runtimeLock.withLock { $0.agentStatus }
    }

    public func publishStatus(_ status: AgentStatus) {
        runtimeLock.withLock { state in
            state.agentStatus = status
            if status == .shutdown {
                state.shutdown = true
            }
        }
        waitersLock.lock()
        let waiters = Array(statusWaiters.values)
        waitersLock.unlock()
        for waiter in waiters {
            waiter.yield(status)
        }
    }

    public func subscribeStatus() -> AsyncStream<AgentStatus> {
        let initial = runtimeLock.withLock { $0.agentStatus }
        return AsyncStream { continuation in
            let id = UUID()
            waitersLock.lock()
            statusWaiters[id] = continuation
            waitersLock.unlock()
            continuation.yield(initial)
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.waitersLock.lock()
                self.statusWaiters.removeValue(forKey: id)
                self.waitersLock.unlock()
            }
        }
    }

    public func emitTurnItemStarted(turnId: String, item: TurnItem) {
        let startedAtMs = nowUnixTimestampMs()
        let event = ItemStartedEvent(
            threadId: threadId,
            turnId: turnId,
            item: item,
            startedAtMs: startedAtMs
        )
        recordEvent(Event(id: turnId, msg: .itemStarted(event)))
        for legacy in event.asLegacyEvents(showRawAgentReasoning: false) {
            recordEvent(Event(id: turnId, msg: legacy))
        }
    }

    public func emitTurnItemCompleted(turnId: String, item: TurnItem, startedAtMs: Int64? = nil) {
        let completedAtMs = nowUnixTimestampMs()
        let event = ItemCompletedEvent(
            threadId: threadId,
            turnId: turnId,
            item: item,
            startedAtMs: startedAtMs,
            completedAtMs: completedAtMs
        )
        recordEvent(Event(id: turnId, msg: .itemCompleted(event)))
        for legacy in event.asLegacyEvents(showRawAgentReasoning: false) {
            recordEvent(Event(id: turnId, msg: legacy))
        }
    }

    deinit {
        let session = runtimeLock.withLock { $0.session }
        if let session {
            Task { await session.shutdown() }
        }
        waitersLock.lock()
        let waiters = Array(statusWaiters.values)
        statusWaiters.removeAll()
        waitersLock.unlock()
        for waiter in waiters {
            waiter.finish()
        }
    }
}
