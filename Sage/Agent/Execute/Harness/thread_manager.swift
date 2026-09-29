//
//  thread_manager.swift
//  CodexCore
//
//  Port of codex-rs/core/src/thread_manager.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Live CodexThread registry (start/get/list/shutdown/spawn edges/sendOp/
//  forkThreadFromHistory) is wired. startThread opens a ThreadSession
//  submission loop. setTurnSampler / attachModelClient drives RegularTask
//  sampling. setTurnToolRunner continues a turn after function calls.
//  Threads opened after installation pick both up. Config,
//  AuthManager, MCP, extensions, and ConfigLayerStack stay deferred.
//  StartThreadOptions remains a thin model/cwd/source snapshot instead of
//  rust Config.
//

import CodexHistory
import CodexProtocol
import CodexUtils
import Foundation
import os

/// Represents a newly created Codex thread, including the first event
/// (which is `EventMsg.sessionConfigured`).
public struct NewThread: Sendable {
    public var threadId: ThreadId
    public var thread: CodexThread
    public var sessionConfigured: SessionConfiguredEvent

    public init(threadId: ThreadId, thread: CodexThread, sessionConfigured: SessionConfiguredEvent) {
        self.threadId = threadId
        self.thread = thread
        self.sessionConfigured = sessionConfigured
    }
}

public enum ForkSnapshot: Equatable, Sendable {
    /// Fork a committed prefix ending strictly before the nth user message.
    case truncateBeforeNthUserMessage(Int)
    /// Fork the current persisted history as if the source thread had been interrupted.
    case interrupted
}

extension ForkSnapshot: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) {
        self = .truncateBeforeNthUserMessage(value)
    }
}

public struct ThreadShutdownReport: Equatable, Sendable {
    public var completed: [ThreadId]
    public var submitFailed: [ThreadId]
    public var timedOut: [ThreadId]

    public init(
        completed: [ThreadId] = [],
        submitFailed: [ThreadId] = [],
        timedOut: [ThreadId] = []
    ) {
        self.completed = completed
        self.submitFailed = submitFailed
        self.timedOut = timedOut
    }
}

public struct StartThreadOptions: Sendable {
    public var model: String?
    public var cwd: String?
    public var source: SessionSource
    public var reservedThreadId: ThreadId?
    public var forkedFromThreadId: ThreadId?

    public init(
        model: String? = nil,
        cwd: String? = nil,
        source: SessionSource = .cli,
        reservedThreadId: ThreadId? = nil,
        forkedFromThreadId: ThreadId? = nil
    ) {
        self.model = model
        self.cwd = cwd
        self.source = source
        self.reservedThreadId = reservedThreadId
        self.forkedFromThreadId = forkedFromThreadId
    }
}

private enum ShutdownOutcome {
    case complete
    case submitFailed
    case timedOut
}

/// Creates threads and keeps live handles. Each inserted thread owns a
/// ThreadSession submission loop.
public final class ThreadManager: @unchecked Sendable {
    public let agentRuntime: LocalAgentRuntime
    private struct State {
        var threads: [ThreadId: CodexThread] = [:]
    }

    private let lock = OSAllocatedUnfairLock(initialState: State())
    /// Installed before `startThread` / spawn. Drives `RegularTask` sampling.
    public var turnSampler: (any TurnSampler)?
    /// Installed before `startThread` / spawn. Runs function calls inside a regular turn.
    public var turnToolRunner: (any TurnToolRunner)?

    public init(agentRuntime: LocalAgentRuntime = LocalAgentRuntime()) {
        self.agentRuntime = agentRuntime
        agentRuntime.attachThreadManager(self)
    }

    public func agentControl(sessionId: SessionId = SessionId()) -> LocalAgentControl {
        agentRuntime.control(sessionId: sessionId)
    }

    public func setTurnSampler(_ sampler: (any TurnSampler)?) {
        turnSampler = sampler
    }

    public func setTurnToolRunner(_ runner: (any TurnToolRunner)?) {
        turnToolRunner = runner
    }

    /// Regular turns sample through this client. Function-call follow-up uses `turnToolRunner`.
    public func attachModelClient(_ client: ModelClient, model: String) {
        setTurnSampler(ModelClientTurnSampler(client: client, model: model))
    }

    public func reserveThreadId() -> ThreadId {
        ThreadId()
    }

    public func startThread(_ options: StartThreadOptions) async throws -> NewThread {
        let threadId = options.reservedThreadId ?? reserveThreadId()
        let cwd = try resolveThreadCwd(options.cwd)
        let model = options.model ?? ""
        let snapshot = ThreadConfigSnapshot(
            model: model,
            sessionSource: options.source,
            forkedFromThreadId: options.forkedFromThreadId,
            parentThreadId: options.source.parentThreadId()
        )
        let newThread = try insertLiveThread(
            threadId: threadId,
            sessionSource: options.source,
            model: model,
            cwd: cwd,
            configSnapshot: snapshot
        )
        if !options.source.isNonRootAgent() {
            agentRuntime.registerSessionRoot(
                currentThreadId: threadId,
                currentParentThreadId: options.source.parentThreadId()
            )
        }
        return newThread
    }

    public func listThreadIds() async -> [ThreadId] {
        lock.withLock { state in
            state.threads.compactMap { threadId, thread in
                thread.sessionSource.isInternal() ? nil : threadId
            }
        }
    }

    public func getThread(_ threadId: ThreadId) async throws -> CodexThread {
        let thread = lock.withLock { $0.threads[threadId] }
        guard let thread, !thread.sessionSource.isInternal() else {
            throw CodexErr.threadNotFound(threadId)
        }
        return thread
    }

    public func listLiveThreadSpawnEdges() async -> [(ThreadId, ThreadId)] {
        lock.withLock { state in
            state.threads.compactMap { threadId, thread in
                if thread.sessionSource.isInternal() {
                    return nil
                }
                switch thread.sessionSource {
                case .subAgent(.threadSpawn(let parentThreadId, _, _, _, _)):
                    return (parentThreadId, threadId)
                default:
                    return nil
                }
            }
        }
    }

    public func listAgentSubtreeThreadIds(_ threadId: ThreadId) async throws -> [ThreadId] {
        var subtreeThreadIds = [threadId]
        var seenThreadIds: Set<ThreadId> = [threadId]
        for descendantId in try await agentRuntime.listLiveAgentSubtreeThreadIds(threadId) {
            if seenThreadIds.insert(descendantId).inserted {
                subtreeThreadIds.append(descendantId)
            }
        }
        return subtreeThreadIds
    }

    public func removeThread(_ threadId: ThreadId) async -> CodexThread? {
        lock.withLock { $0.threads.removeValue(forKey: threadId) }
    }

    public func removeThreadForClient(_ threadId: ThreadId) async throws -> CodexThread? {
        enum Outcome {
            case notInternal(CodexThread?)
            case internalThread
        }
        let outcome = lock.withLock { state -> Outcome in
            if state.threads[threadId]?.sessionSource.isInternal() == true {
                return .internalThread
            }
            return .notInternal(state.threads.removeValue(forKey: threadId))
        }
        switch outcome {
        case .internalThread:
            throw CodexErr.invalidRequest(
                "live internal threads can only be removed by their owner"
            )
        case .notInternal(let thread):
            return thread
        }
    }

    public func removeThreadIfMatches(_ threadId: ThreadId, expected: CodexThread) async -> CodexThread? {
        lock.withLock { state in
            guard let thread = state.threads[threadId], thread === expected else {
                return nil
            }
            return state.threads.removeValue(forKey: threadId)
        }
    }

    public func peekThread(_ threadId: ThreadId) -> CodexThread? {
        lock.withLock { $0.threads[threadId] }
    }

    public func forkThreadFromHistory(
        _ snapshot: ForkSnapshot,
        options: StartThreadOptions,
        history: InitialHistory
    ) async throws -> NewThread {
        var options = options
        let sourceThreadId: ThreadId?
        switch history {
        case .resumed(let resumed):
            sourceThreadId = resumed.conversationId
        case .forked:
            sourceThreadId = history.forkedFromId()
        case .new, .cleared:
            sourceThreadId = nil
        }
        if let sourceThreadId, let source = peekThread(sourceThreadId) {
            if options.model == nil {
                options.model = source.configSnapshot().model
            }
            if options.cwd == nil {
                options.cwd = source.startup.cwd.path
            }
        }
        options.forkedFromThreadId = sourceThreadId ?? options.forkedFromThreadId
        let forkedItems = forkHistoryItems(history.getRolloutItems(), snapshot: snapshot)
        let newThread = try await startThread(options)
        newThread.thread.replaceHistory(forkedItems)
        return newThread
    }

    public func sendOp(
        _ threadId: ThreadId,
        op: ThreadOp,
        parentTurnId: String? = nil,
        rootTurnId: String? = nil
    ) async throws -> String {
        _ = parentTurnId
        _ = rootTurnId
        let thread = try await getThread(threadId)
        if case .shutdown = op {
            try await thread.shutdownAndWait()
        }
        return thread.submit(op)
    }

    /// Tries to shut down all tracked threads. Session IO is not wired, so
    /// shutdown completes the live latch immediately; `timeout` is retained
    /// for the rust signature.
    public func shutdownAllThreadsBounded(_ timeout: Duration) async -> ThreadShutdownReport {
        _ = timeout
        let threads = lock.withLock { state in
            state.threads.map { ($0.key, $0.value) }
        }

        var report = ThreadShutdownReport()
        for (threadId, thread) in threads {
            let outcome: ShutdownOutcome
            do {
                try await thread.shutdownAndWait()
                outcome = .complete
            } catch {
                outcome = .submitFailed
            }
            switch outcome {
            case .complete:
                report.completed.append(threadId)
            case .submitFailed:
                report.submitFailed.append(threadId)
            case .timedOut:
                report.timedOut.append(threadId)
            }
        }

        lock.withLock { state in
            for threadId in report.completed {
                state.threads.removeValue(forKey: threadId)
            }
        }

        report.completed.sort { $0.description < $1.description }
        report.submitFailed.sort { $0.description < $1.description }
        report.timedOut.sort { $0.description < $1.description }
        return report
    }

    func insertLiveThread(
        threadId: ThreadId,
        sessionSource: SessionSource,
        model: String,
        modelProviderId: String = "",
        cwd: AbsolutePathBuf,
        configSnapshot: ThreadConfigSnapshot
    ) throws -> NewThread {
        var event = SessionConfiguredEvent(
            sessionId: SessionId(threadId),
            threadId: threadId,
            model: model,
            modelProviderId: modelProviderId,
            approvalPolicy: configSnapshot.approvalPolicy,
            permissionProfile: .readOnly(),
            cwd: cwd
        )
        event.parentThreadId = configSnapshot.parentThreadId ?? sessionSource.parentThreadId()
        event.threadSource = configSnapshot.threadSource
        event.serviceTier = configSnapshot.serviceTier
        event.forkedFromId = configSnapshot.forkedFromThreadId
        let thread = CodexThread(
            threadId: threadId,
            startup: ThreadStartupMetadata(from: event),
            sessionSource: sessionSource,
            configSnapshot: configSnapshot
        )
        let inserted = lock.withLock { state -> Bool in
            if state.threads[threadId] != nil {
                return false
            }
            state.threads[threadId] = thread
            return true
        }
        if !inserted {
            throw CodexErr.invalidRequest("thread \(threadId) is already running")
        }
        thread.openLiveSession(sampler: turnSampler, toolRunner: turnToolRunner)
        return NewThread(threadId: threadId, thread: thread, sessionConfigured: event)
    }
}

func resolveThreadCwd(_ cwd: String?) throws -> AbsolutePathBuf {
    do {
        if let cwd, !cwd.isEmpty {
            if cwd.hasPrefix("/") {
                return try AbsolutePathBuf.fromAbsolutePath(cwd)
            }
            return AbsolutePathBuf.resolvePathAgainstBase(
                cwd,
                basePath: FileManager.default.currentDirectoryPath
            )
        }
        return try AbsolutePathBuf.currentDir()
    } catch {
        throw CodexErr.invalidRequest("invalid thread cwd: \(error)")
    }
}

public func forkHistoryItems(
    _ items: [RolloutItem],
    snapshot: ForkSnapshot
) -> [RolloutItem] {
    switch snapshot {
    case .truncateBeforeNthUserMessage(let n):
        return truncateRolloutBeforeNthUserMessageFromStart(items, nFromStart: n)
    case .interrupted:
        return items
    }
}
