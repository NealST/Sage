//
//  registry.swift
//  CodexCore
//
//  Port of codex-rs/core/src/agent/registry.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  `Mutex` / `AtomicUsize` map to `OSAllocatedUnfairLock`. Nickname-pool
//  reset does not emit the `codex.multi_agent.nickname_pool_reset` otel
//  counter until Phase 10.
//

import CodexProtocol
import Foundation
import os

public func formatAgentNickname(_ name: String, nicknameResetCount: Int) -> String {
    if nicknameResetCount == 0 {
        return name
    }
    let value = nicknameResetCount + 1
    let suffix: String
    switch value % 100 {
    case 11, 12, 13:
        suffix = "th"
    default:
        switch value % 10 {
        case 1:
            suffix = "st"
        case 2:
            suffix = "nd"
        case 3:
            suffix = "rd"
        default:
            suffix = "th"
        }
    }
    return "\(name) the \(value)\(suffix)"
}

func sessionDepth(_ sessionSource: SessionSource) -> Int32 {
    switch sessionSource {
    case .subAgent(.threadSpawn(_, let depth, _, _, _)):
        return depth
    default:
        return 0
    }
}

public func nextThreadSpawnDepth(_ sessionSource: SessionSource) -> Int32 {
    let depth = sessionDepth(sessionSource)
    if depth == Int32.max { return Int32.max }
    return depth + 1
}

public func exceedsThreadSpawnDepthLimit(depth: Int32, maxDepth: Int32) -> Bool {
    depth > maxDepth
}

private struct RegisteredAgent {
    var path: String
    var evictedEnvironments: [TurnEnvironmentSelection]?

    init(path: String) {
        self.path = path
        self.evictedEnvironments = nil
    }
}

private struct ActiveAgents {
    var agentTree: [String: AgentMetadata] = [:]
    var threadPaths: [ThreadId: RegisteredAgent] = [:]
    var usedAgentNicknames: Set<String> = []
    var nicknameResetCount: Int = 0
}

public final class AgentRegistry: @unchecked Sendable {
    private struct State {
        var activeAgents = ActiveAgents()
        var totalCount: Int = 0
    }

    private let lock = OSAllocatedUnfairLock(initialState: State())

    public init() {}

    public func reserveSpawnSlot(maxThreads: Int?) throws -> SpawnReservation {
        try lock.withLock { state in
            if let maxThreads {
                if state.totalCount >= maxThreads {
                    throw CodexErr.agentLimitReached(maxThreads: maxThreads)
                }
                state.totalCount += 1
            } else {
                state.totalCount += 1
            }
        }
        return SpawnReservation(state: self)
    }

    public func releaseSpawnedThread(_ threadId: ThreadId) {
        let removedCountedAgent = lock.withLock { state -> Bool in
            guard let agent = state.activeAgents.threadPaths.removeValue(forKey: threadId),
                  let metadata = state.activeAgents.agentTree.removeValue(forKey: agent.path)
            else {
                return false
            }
            return !(metadata.agentPath?.isRoot ?? false)
        }
        if removedCountedAgent {
            lock.withLock { $0.totalCount -= 1 }
        }
    }

    public func registerRootThread(_ threadId: ThreadId) {
        lock.withLock { state in
            let rootPath = AgentPath.rootString
            let existing = state.activeAgents.agentTree[rootPath]
            let metadata = existing ?? AgentMetadata(
                agentId: threadId,
                agentPath: .root()
            )
            if existing == nil {
                state.activeAgents.agentTree[rootPath] = metadata
            }
            if let rootThreadId = (existing ?? metadata).agentId ?? metadata.agentId {
                state.activeAgents.threadPaths[rootThreadId] = RegisteredAgent(path: rootPath)
            }
        }
    }

    public func agentIdForPath(_ agentPath: AgentPath) -> ThreadId? {
        lock.withLock { state in
            state.activeAgents.agentTree[agentPath.asStr]?.agentId
        }
    }

    public func agentMetadataForThread(_ threadId: ThreadId) -> AgentMetadata? {
        lock.withLock { state in
            guard let agent = state.activeAgents.threadPaths[threadId] else { return nil }
            return state.activeAgents.agentTree[agent.path]
        }
    }

    public func saveEvictedEnvironments(
        _ threadId: ThreadId,
        environments: [TurnEnvironmentSelection]
    ) {
        lock.withLock { state in
            state.activeAgents.threadPaths[threadId]?.evictedEnvironments = environments
        }
    }

    public func evictedEnvironments(_ threadId: ThreadId) -> [TurnEnvironmentSelection]? {
        lock.withLock { state in
            state.activeAgents.threadPaths[threadId]?.evictedEnvironments
        }
    }

    public func clearEvictedEnvironments(_ threadId: ThreadId) {
        lock.withLock { state in
            state.activeAgents.threadPaths[threadId]?.evictedEnvironments = nil
        }
    }

    public func liveAgents() -> [AgentMetadata] {
        lock.withLock { state in
            state.activeAgents.agentTree.values.filter { metadata in
                metadata.agentId != nil && !(metadata.agentPath?.isRoot ?? false)
            }
        }
    }

    func registerSpawnedThread(_ agentMetadata: AgentMetadata) {
        guard let threadId = agentMetadata.agentId else { return }
        lock.withLock { state in
            let key = agentMetadata.agentPath.map(\.asStr) ?? "thread:\(threadId)"
            if let nickname = agentMetadata.agentNickname {
                state.activeAgents.usedAgentNicknames.insert(nickname)
            }
            if let previous = state.activeAgents.threadPaths.updateValue(
                RegisteredAgent(path: key), forKey: threadId
            ), previous.path != key {
                state.activeAgents.agentTree.removeValue(forKey: previous.path)
            }
            if let previousMetadata = state.activeAgents.agentTree.updateValue(
                agentMetadata, forKey: key
            ), let previousThreadId = previousMetadata.agentId, previousThreadId != threadId {
                state.activeAgents.threadPaths.removeValue(forKey: previousThreadId)
            }
        }
    }

    func reserveAgentNickname(names: [String], preferred: String?) -> String? {
        lock.withLock { state in
            let agentNickname: String
            if let preferred {
                agentNickname = preferred
            } else {
                if names.isEmpty { return nil }
                let availableNames = names
                    .map { formatAgentNickname($0, nicknameResetCount: state.activeAgents.nicknameResetCount) }
                    .filter { !state.activeAgents.usedAgentNicknames.contains($0) }
                if let name = availableNames.randomElement() {
                    agentNickname = name
                } else {
                    state.activeAgents.usedAgentNicknames.removeAll()
                    state.activeAgents.nicknameResetCount += 1
                    guard let chosen = names.randomElement() else { return nil }
                    agentNickname = formatAgentNickname(
                        chosen, nicknameResetCount: state.activeAgents.nicknameResetCount)
                }
            }
            state.activeAgents.usedAgentNicknames.insert(agentNickname)
            return agentNickname
        }
    }

    func reserveAgentPath(_ agentPath: AgentPath) throws {
        try lock.withLock { state in
            if state.activeAgents.agentTree[agentPath.asStr] != nil {
                throw CodexErr.unsupportedOperation(
                    "agent path `\(agentPath.asStr)` already exists"
                )
            }
            state.activeAgents.agentTree[agentPath.asStr] = AgentMetadata(agentPath: agentPath)
        }
    }

    func releaseReservedAgentPath(_ agentPath: AgentPath) {
        lock.withLock { state in
            if state.activeAgents.agentTree[agentPath.asStr]?.agentId == nil {
                state.activeAgents.agentTree.removeValue(forKey: agentPath.asStr)
            }
        }
    }

    func decrementTotalCount() {
        lock.withLock { $0.totalCount -= 1 }
    }
}

public final class SpawnReservation {
    private let state: AgentRegistry
    private var active: Bool
    private var reservedAgentNickname: String?
    private var reservedAgentPath: AgentPath?

    init(state: AgentRegistry) {
        self.state = state
        self.active = true
        self.reservedAgentNickname = nil
        self.reservedAgentPath = nil
    }

    deinit {
        if active {
            if let agentPath = reservedAgentPath {
                state.releaseReservedAgentPath(agentPath)
            }
            state.decrementTotalCount()
        }
    }

    public func reserveAgentNicknameWithPreference(
        names: [String],
        preferred: String?
    ) throws -> String {
        guard let agentNickname = state.reserveAgentNickname(names: names, preferred: preferred) else {
            throw CodexErr.unsupportedOperation("no available agent nicknames")
        }
        reservedAgentNickname = agentNickname
        return agentNickname
    }

    public func reserveAgentPath(_ agentPath: AgentPath) throws {
        try state.reserveAgentPath(agentPath)
        reservedAgentPath = agentPath
    }

    public func commit(_ agentMetadata: AgentMetadata) {
        reservedAgentNickname = nil
        reservedAgentPath = nil
        state.registerSpawnedThread(agentMetadata)
        active = false
    }
}
