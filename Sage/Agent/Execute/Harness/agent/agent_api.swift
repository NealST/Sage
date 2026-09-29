//
//  agent_api.swift
//  CodexCore
//
//  Port of codex-rs/core/src/agent/api.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  R4a: basename `api.swift` is reserved for `agent/control/control_api.swift`.
//  `Config` is not in CodexCore; `SpawnRequest` / `SendRequest` omit it.
//  Boxed Rust futures become Swift `async` methods.
//

import CodexProtocol
import Foundation

/// Coordinates agent operations and shared state through a local or host backend.
public protocol AgentControl: Sendable {
    func identity() -> SessionId

    func resolve(
        caller: ThreadId,
        parent: ThreadId?,
        source: SessionSource,
        target: String
    ) async throws -> ThreadId

    func spawn(_ request: SpawnRequest) async throws -> (LiveAgent, ThreadConfigSnapshot)

    func send(_ request: SendRequest) async throws -> DeliveryReceipt

    func ensureChildLoaded(parent: ThreadId, child: ThreadId) async throws

    func interrupt(
        caller: ThreadId,
        target: AgentTarget,
        version: MultiAgentVersion
    ) async throws -> AgentInfo

    func list(
        caller: ThreadId,
        parent: ThreadId?,
        source: SessionSource,
        pathPrefix: String?
    ) async throws -> [LiveAgent]

    func childAgentPaths(parent: ThreadId) async -> [AgentPath]

    func checkTurnAdmission(version: MultiAgentVersion, source: SessionSource) throws

    func admitTurn(
        version: MultiAgentVersion,
        source: SessionSource
    ) -> AgentExecutionGuard?

    func recordUsage(_ usage: TokenUsage) async throws

    func turnFinished(outcome: AgentTurnOutcome) async

    func serviceTier() -> String?

    func propagateConfigUpdate(_ update: AgentConfigUpdate)

    func getGuardianPackage(agent: ThreadId) async -> GuardianRootSnapshot?

    func pendingBudgetReminder(agent: ThreadId, window: String) async -> RolloutBudgetReminder?

    func markBudgetReminderDelivered(
        agent: ThreadId,
        window: String,
        reminder: RolloutBudgetReminder
    ) async
}

/// References resolve relative to the registered caller.
public enum AgentTarget: Equatable, Sendable {
    case id(ThreadId)
    case reference(String)
}

/// Observes existing registry metadata and runtime snapshots without loading an agent.
public enum AgentInfo: Equatable {
    case loaded(agent: LiveAgent, config: ThreadConfigSnapshot)
    case unloaded(AgentMetadata)

    public func metadata() -> AgentMetadata {
        switch self {
        case .loaded(let agent, _):
            return agent.metadata
        case .unloaded(let metadata):
            return metadata
        }
    }

    public func status() -> AgentStatus? {
        switch self {
        case .loaded(let agent, _):
            return agent.status
        case .unloaded:
            return nil
        }
    }
}

public enum AgentInput: Equatable, Sendable {
    case userInput([UserInput])
    case message(message: AgentMessage, mode: MessageDeliveryMode)
}

public struct SpawnRequest: Equatable {
    public var caller: ThreadId
    public var input: AgentInput
    public var source: SessionSource
    public var options: SpawnAgentOptions

    public init(
        caller: ThreadId,
        input: AgentInput,
        source: SessionSource,
        options: SpawnAgentOptions
    ) {
        self.caller = caller
        self.input = input
        self.source = source
        self.options = options
    }
}

public struct SendRequest: Equatable {
    public var caller: ThreadId
    public var target: AgentTarget
    public var input: AgentInput
    public var startOptions: TurnStartOptions

    public init(
        caller: ThreadId,
        target: AgentTarget,
        input: AgentInput,
        startOptions: TurnStartOptions
    ) {
        self.caller = caller
        self.target = target
        self.input = input
        self.startOptions = startOptions
    }
}

public struct DeliveryReceipt: Equatable, Sendable {
    public var threadId: ThreadId
    public var metadata: AgentMetadata
    public var submissionId: String

    public init(threadId: ThreadId, metadata: AgentMetadata, submissionId: String) {
        self.threadId = threadId
        self.metadata = metadata
        self.submissionId = submissionId
    }
}

public struct AgentTurnOutcome: Equatable, Sendable {
    public var threadId: ThreadId
    public var turnId: String
    public var source: SessionSource
    public var parentTurnId: String?
    public var initiatingAgentPath: AgentPath?
    public var status: AgentStatus

    public init(
        threadId: ThreadId,
        turnId: String,
        source: SessionSource,
        parentTurnId: String? = nil,
        initiatingAgentPath: AgentPath? = nil,
        status: AgentStatus
    ) {
        self.threadId = threadId
        self.turnId = turnId
        self.source = source
        self.parentTurnId = parentTurnId
        self.initiatingAgentPath = initiatingAgentPath
        self.status = status
    }
}

/// Settings shared by the tree. A service tier of `nil` restores the default tier.
public enum AgentConfigUpdate: Equatable, Sendable {
    case serviceTier(String?)
}
