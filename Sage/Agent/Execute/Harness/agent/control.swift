//
//  control.swift
//  CodexCore
//
//  Port of codex-rs/core/src/agent/control.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Registry spawn/close/list/inspect and in-memory mailbox send run without
//  Session. Live thread create and history fork wait on ThreadManager.
//  Listed/spawned agents start as `.pendingInit` until a status update.
//

import CodexProtocol
import Foundation
import os

public struct QueuedAgentDelivery: Equatable, Sendable {
    public var submissionId: String
    public var input: AgentInput

    public init(submissionId: String, input: AgentInput) {
        self.submissionId = submissionId
        self.input = input
    }
}

public final class AgentDeliveryState: @unchecked Sendable {
    private struct State {
        var status: [ThreadId: AgentStatus] = [:]
        var mailbox: [ThreadId: [QueuedAgentDelivery]] = [:]
        var activity: Set<ThreadId> = []
    }

    private let lock = OSAllocatedUnfairLock(initialState: State())

    public init() {}

    public func setStatus(_ threadId: ThreadId, _ status: AgentStatus) {
        lock.withLock { $0.status[threadId] = status }
    }

    public func status(_ threadId: ThreadId) -> AgentStatus? {
        lock.withLock { $0.status[threadId] }
    }

    public func enqueue(threadId: ThreadId, input: AgentInput) -> String {
        let submissionId = UUID().uuidString.lowercased()
        lock.withLock { state in
            state.mailbox[threadId, default: []].append(
                QueuedAgentDelivery(submissionId: submissionId, input: input)
            )
            state.activity.insert(threadId)
        }
        return submissionId
    }

    public func mailbox(_ threadId: ThreadId) -> [QueuedAgentDelivery] {
        lock.withLock { $0.mailbox[threadId] ?? [] }
    }

    public func consumeActivity(_ threadId: ThreadId) -> Bool {
        lock.withLock { state in
            state.activity.remove(threadId) != nil
        }
    }

    public func hasActivity(_ threadId: ThreadId) -> Bool {
        lock.withLock { $0.activity.contains(threadId) }
    }

    public func remove(_ threadId: ThreadId) {
        lock.withLock { state in
            state.status.removeValue(forKey: threadId)
            state.mailbox.removeValue(forKey: threadId)
            state.activity.remove(threadId)
        }
    }
}

public final class LocalAgentRuntime: @unchecked Sendable {
    public let registry: AgentRegistry
    public let rolloutBudget: RolloutBudget
    public let agentExecutionLimiter: AgentExecutionLimiter
    public let residency: V2Residency
    public let delivery: AgentDeliveryState
    private let serviceTierLock = OSAllocatedUnfairLock<String?>(initialState: nil)

    public init(
        registry: AgentRegistry = AgentRegistry(),
        rolloutBudget: RolloutBudget = RolloutBudget(),
        agentExecutionLimiter: AgentExecutionLimiter = AgentExecutionLimiter(),
        residency: V2Residency = V2Residency(),
        delivery: AgentDeliveryState = AgentDeliveryState()
    ) {
        self.registry = registry
        self.rolloutBudget = rolloutBudget
        self.agentExecutionLimiter = agentExecutionLimiter
        self.residency = residency
        self.delivery = delivery
    }

    public func generateThreadId() -> ThreadId { ThreadId() }

    public func registerSessionRoot(
        currentThreadId: ThreadId,
        currentParentThreadId: ThreadId?
    ) {
        if currentParentThreadId == nil {
            registry.registerRootThread(currentThreadId)
        }
    }

    public func ensureAgentKnown(_ agentId: ThreadId) throws -> AgentMetadata {
        if let metadata = registry.agentMetadataForThread(agentId) {
            return metadata
        }
        throw CodexErr.threadNotFound(agentId)
    }

    public func control(sessionId: SessionId) -> LocalAgentControl {
        LocalAgentControl(sessionId: sessionId, runtime: self)
    }

    public func rootServiceTier() -> String? {
        serviceTierLock.withLock { $0 }
    }

    public func setRootServiceTier(_ serviceTier: String?) {
        serviceTierLock.withLock { $0 = serviceTier }
    }

    public func resolvePathReference(
        currentAgentPath: AgentPath,
        agentReference: String
    ) throws -> ThreadId {
        let agentPath: AgentPath
        do {
            agentPath = try currentAgentPath.resolve(agentReference)
        } catch {
            throw CodexErr.unsupportedOperation(String(describing: error))
        }
        if let threadId = registry.agentIdForPath(agentPath) {
            return threadId
        }
        throw CodexErr.unsupportedOperation(
            "live agent path `\(agentPath.asStr)` not found"
        )
    }

    public func resolveAgentReference(
        currentSessionSource: SessionSource,
        agentReference: String
    ) throws -> ThreadId {
        let currentAgentPath = currentSessionSource.getAgentPath() ?? .root()
        return try resolvePathReference(
            currentAgentPath: currentAgentPath,
            agentReference: agentReference
        )
    }
}

public final class LocalAgentControl: @unchecked Sendable {
    public let sessionId: SessionId
    public let runtime: LocalAgentRuntime

    public init(
        sessionId: SessionId = SessionId(),
        runtime: LocalAgentRuntime = LocalAgentRuntime()
    ) {
        self.sessionId = sessionId
        self.runtime = runtime
    }

    public func identity() -> SessionId { sessionId }

    public func checkTurnAdmission(
        version: MultiAgentVersion,
        source: SessionSource
    ) throws {
        try ensureExecutionCapacity(version, sessionSource: source)
    }

    public func admitTurn(
        version: MultiAgentVersion,
        source: SessionSource
    ) -> AgentExecutionGuard? {
        executionGuard(version, sessionSource: source)
    }

    public func serviceTier() -> String? {
        runtime.rootServiceTier()
    }

    public func propagateConfigUpdate(_ update: AgentConfigUpdate) {
        switch update {
        case .serviceTier(let tier):
            runtime.setRootServiceTier(tier)
        }
    }

    public func spawn(_ request: SpawnRequest) async throws -> (LiveAgent, ThreadConfigSnapshot) {
        if isV2ResidentSessionSource(request.source) {
            try checkTurnAdmission(version: .v2, source: request.source)
        }
        let reservation = try runtime.registry.reserveSpawnSlot(maxThreads: nil)
        let sessionSource: SessionSource
        let metadata: AgentMetadata
        if case .subAgent(
            .threadSpawn(let parentThreadId, let depth, let agentPath, _, let agentRole)
        ) = request.source {
            (sessionSource, metadata) = try prepareThreadSpawn(
                reservation: reservation,
                parentThreadId: parentThreadId,
                depth: depth,
                agentPath: agentPath,
                agentRole: agentRole,
                preferredAgentNickname: request.source.getNickname()
            )
        } else {
            sessionSource = request.source
            metadata = AgentMetadata()
        }
        let threadId = runtime.generateThreadId()
        var committed = metadata
        committed.agentId = threadId
        reservation.commit(committed)
        runtime.delivery.setStatus(threadId, .pendingInit)
        _ = runtime.delivery.enqueue(threadId: threadId, input: request.input)
        let live = LiveAgent(threadId: threadId, metadata: committed, status: .pendingInit)
        let snapshot = ThreadConfigSnapshot(
            model: "",
            sessionSource: sessionSource,
            parentThreadId: request.options.parentThreadId ?? sessionSource.parentThreadId()
        )
        return (live, snapshot)
    }

    public func send(_ request: SendRequest) async throws -> DeliveryReceipt {
        let target = try resolveTarget(caller: request.caller, target: request.target)
        let metadata = try runtime.ensureAgentKnown(target)
        switch request.input {
        case .userInput(let items) where items.isEmpty:
            throw CodexErr.invalidRequest("Items can't be empty")
        case .message(let message, _) where message.isEmpty:
            throw CodexErr.invalidRequest("Empty message can't be sent to an agent")
        default:
            break
        }
        let submissionId = runtime.delivery.enqueue(threadId: target, input: request.input)
        if case .message(_, .triggerTurn) = request.input {
            runtime.delivery.setStatus(target, .running)
        } else if case .userInput = request.input {
            runtime.delivery.setStatus(target, .running)
        }
        return DeliveryReceipt(threadId: target, metadata: metadata, submissionId: submissionId)
    }

    public func ensureChildLoaded(parent: ThreadId, child: ThreadId) async throws {
        let parentMetadata = try runtime.ensureAgentKnown(parent)
        let childMetadata = try runtime.ensureAgentKnown(child)
        guard let parentPath = parentMetadata.agentPath, let childPath = childMetadata.agentPath else {
            throw CodexErr.invalidRequest(
                "cannot resume multi-agent v2 child \(child): parent ownership is unavailable; resume the parent first"
            )
        }
        let prefix = "\(parentPath.asStr)/"
        guard childPath.asStr.hasPrefix(prefix) else {
            throw CodexErr.invalidRequest(
                "cannot resume multi-agent v2 child \(child): recorded parent ownership is inconsistent"
            )
        }
    }

    public func interrupt(
        caller: ThreadId,
        target: AgentTarget,
        version: MultiAgentVersion
    ) async throws -> AgentInfo {
        let target = try resolveTarget(caller: caller, target: target)
        switch version {
        case .disabled, .v1:
            let snapshot = try await inspectAgent(target)
            try await interruptAgent(target)
            return snapshot
        case .v2:
            return try await interruptSpawnedAgent(caller: caller, target: target)
        }
    }

    public func getAgentMetadata(_ agentId: ThreadId) -> AgentMetadata? {
        runtime.registry.agentMetadataForThread(agentId)
    }

    public func getStatus(_ agentId: ThreadId) async -> AgentStatus {
        runtime.delivery.status(agentId) ?? .notFound
    }

    public func list(
        caller: ThreadId,
        parent: ThreadId?,
        source: SessionSource,
        pathPrefix: String?
    ) async throws -> [LiveAgent] {
        runtime.registerSessionRoot(currentThreadId: caller, currentParentThreadId: parent)
        let resolvedPrefix: AgentPath?
        if let pathPrefix {
            do {
                resolvedPrefix = try (source.getAgentPath() ?? .root()).resolve(pathPrefix)
            } catch {
                throw CodexErr.unsupportedOperation(String(describing: error))
            }
        } else {
            resolvedPrefix = nil
        }

        var liveAgents = runtime.registry.liveAgents()
        liveAgents.sort { left, right in
            let leftPath = left.agentPath?.asStr ?? ""
            let rightPath = right.agentPath?.asStr ?? ""
            if leftPath != rightPath {
                return leftPath < rightPath
            }
            return (left.agentId?.description ?? "") < (right.agentId?.description ?? "")
        }

        let rootPath = AgentPath.root()
        var agents: [LiveAgent] = []
        agents.reserveCapacity(liveAgents.count + 1)
        if resolvedPrefix.map({ agentMatchesPrefix(rootPath, prefix: $0) }) ?? true,
           let rootThreadId = runtime.registry.agentIdForPath(rootPath)
        {
            agents.append(
                liveSnapshot(
                    threadId: rootThreadId,
                    metadata: AgentMetadata(agentId: rootThreadId, agentPath: rootPath)
                )
            )
        }

        for metadata in liveAgents {
            guard let threadId = metadata.agentId else { continue }
            if let prefix = resolvedPrefix, !agentMatchesPrefix(metadata.agentPath, prefix: prefix) {
                continue
            }
            agents.append(liveSnapshot(threadId: threadId, metadata: metadata))
        }
        return agents
    }

    public func childAgentPaths(parent: ThreadId) async -> [AgentPath] {
        guard let parentPath = runtime.registry.agentMetadataForThread(parent)?.agentPath else {
            return []
        }
        let parentPrefix = "\(parentPath.asStr)/"
        var agentPaths = runtime.registry.liveAgents().compactMap(\.agentPath).filter { path in
            guard let name = path.asStr.stripPrefix(parentPrefix) else { return false }
            return !name.contains("/")
        }
        agentPaths.sort()
        return agentPaths
    }

    public func turnFinished(outcome: AgentTurnOutcome) async {
        runtime.delivery.setStatus(outcome.threadId, outcome.status)
        await notifyParentOfTerminalTurn(outcome)
    }

    public func sendInput(
        _ agentId: ThreadId,
        input: [UserInput],
        startOptions: TurnStartOptions
    ) async throws -> String {
        let receipt = try await send(
            SendRequest(
                caller: agentId,
                target: .id(agentId),
                input: .userInput(input),
                startOptions: startOptions
            )
        )
        return receipt.submissionId
    }

    func liveSnapshot(threadId: ThreadId, metadata: AgentMetadata) -> LiveAgent {
        LiveAgent(
            threadId: threadId,
            metadata: metadata,
            status: runtime.delivery.status(threadId) ?? .pendingInit
        )
    }

    public func getGuardianPackage(agent: ThreadId) async -> GuardianRootSnapshot? {
        nil
    }
}

extension LocalAgentControl: AgentControl {
    public func resolve(
        caller: ThreadId,
        parent: ThreadId?,
        source: SessionSource,
        target: String
    ) async throws -> ThreadId {
        if let threadId = try? ThreadId.fromString(target) {
            return threadId
        }
        return try runtime.resolveAgentReference(
            currentSessionSource: source,
            agentReference: target
        )
    }

    public func recordUsage(_ usage: TokenUsage) async throws {
        try recordRolloutBudgetUsage(usage)
    }

    public func pendingBudgetReminder(agent: ThreadId, window: String) async -> RolloutBudgetReminder? {
        pendingBudgetReminder(threadId: agent, windowId: window)
    }

    public func markBudgetReminderDelivered(
        agent: ThreadId,
        window: String,
        reminder: RolloutBudgetReminder
    ) async {
        markBudgetReminderDelivered(threadId: agent, windowId: window, reminder: reminder)
    }
}

public enum AgentControlInit {
    case local(LocalAgentControl)
    case provided(control: any AgentControl, runtime: LocalAgentRuntime)

    public func runtime() -> LocalAgentRuntime {
        switch self {
        case .local(let control):
            return control.runtime
        case .provided(_, let runtime):
            return runtime
        }
    }
}

func agentMatchesPrefix(_ agentPath: AgentPath?, prefix: AgentPath) -> Bool {
    if prefix.isRoot { return true }
    return agentPath.map { path in
        path == prefix
            || path.asStr.stripPrefix(prefix.asStr).map { $0.hasPrefix("/") } ?? false
    } ?? false
}

func agentMatchesPrefix(_ agentPath: AgentPath, prefix: AgentPath) -> Bool {
    agentMatchesPrefix(Optional(agentPath), prefix: prefix)
}

public func renderInputPreview(_ input: [UserInput]) -> String {
    input.map { item in
        switch item {
        case .text(let text, _):
            return text
        case .image:
            return "[image]"
        case .localImage(let path, _):
            return "[local_image:\(path)]"
        case .audio:
            return "[audio]"
        case .localAudio(let path):
            return "[local_audio:\(path)]"
        case .skill(let name, let path):
            return "[skill:$\(name)](\(path))"
        case .mention(let name, let path):
            return "[mention:$\(name)](\(path))"
        }
    }
    .joined(separator: "\n")
}

func threadSpawnDepth(_ sessionSource: SessionSource) -> Int32? {
    switch sessionSource {
    case .subAgent(.threadSpawn(_, let depth, _, _, _)):
        return depth
    default:
        return nil
    }
}

private extension String {
    func stripPrefix(_ prefix: String) -> String? {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : nil
    }
}
