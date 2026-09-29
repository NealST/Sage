//
//  types.swift
//  CodexCore
//
//  Port of codex-rs/core/src/agent/types.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  `MultiAgentRoleInstructions` lives in the prompts crate; this file keeps
//  a type-shaped stand-in until that crate is ported. `AgentExecutionGuard`
//  holds an opaque token instead of a Rust trait object.
//

import CodexProtocol
import Foundation

/// Registry identity shared by loaded and unloaded agents.
/// Registered agents have an `agent_id`; a reserved spawn can still be awaiting its ID.
public struct AgentMetadata: Equatable, Sendable {
    public var agentId: ThreadId?
    public var agentPath: AgentPath?
    public var agentNickname: String?
    public var agentRole: String?

    public init(
        agentId: ThreadId? = nil,
        agentPath: AgentPath? = nil,
        agentNickname: String? = nil,
        agentRole: String? = nil
    ) {
        self.agentId = agentId
        self.agentPath = agentPath
        self.agentNickname = agentNickname
        self.agentRole = agentRole
    }
}

public enum SpawnAgentForkMode: Equatable, Sendable {
    case fullHistory
    case lastNTurns(Int)
}

public struct SpawnAgentOptions: Equatable {
    public var forkParentSpawnCallId: String?
    public var forkMode: SpawnAgentForkMode?
    public var parentThreadId: ThreadId?
    public var parentTurnId: String?
    /// Attribute delegated usage to the turn that initiated it.
    public var turnTrigger: String?
    public var rootTurnId: String?
    public var environments: [TurnEnvironmentSelection]?
    public var multiAgentV2UsageHints: ResolvedMultiAgentV2UsageHints?
    public var cyberAccessProgram: CyberAccessProgram?

    public init(
        forkParentSpawnCallId: String? = nil,
        forkMode: SpawnAgentForkMode? = nil,
        parentThreadId: ThreadId? = nil,
        parentTurnId: String? = nil,
        turnTrigger: String? = nil,
        rootTurnId: String? = nil,
        environments: [TurnEnvironmentSelection]? = nil,
        multiAgentV2UsageHints: ResolvedMultiAgentV2UsageHints? = nil,
        cyberAccessProgram: CyberAccessProgram? = nil
    ) {
        self.forkParentSpawnCallId = forkParentSpawnCallId
        self.forkMode = forkMode
        self.parentThreadId = parentThreadId
        self.parentTurnId = parentTurnId
        self.turnTrigger = turnTrigger
        self.rootTurnId = rootTurnId
        self.environments = environments
        self.multiAgentV2UsageHints = multiAgentV2UsageHints
        self.cyberAccessProgram = cyberAccessProgram
    }
}

/// Identity and status observed from a loaded agent, without a handle to its runtime.
public struct LiveAgent: Equatable, Sendable {
    public var threadId: ThreadId
    public var metadata: AgentMetadata
    public var status: AgentStatus

    public init(threadId: ThreadId, metadata: AgentMetadata, status: AgentStatus) {
        self.threadId = threadId
        self.metadata = metadata
        self.status = status
    }
}

/// Type stand-in for `codex_prompts::MultiAgentRoleInstructions`.
public enum MultiAgentRoleInstructions: Equatable, Sendable {
    case configured(String)
    case composed(
        base: String,
        marked: Bool,
        omitUpdatePlanInstructions: Bool,
        maxConcurrency: Int,
        waitAgentEnabled: Bool,
        exposeModelOverrides: Bool
    )

    public static func matchesText(_ text: String) -> Bool {
        text.contains("<multi_agent_role>")
    }
}

public struct ResolvedMultiAgentV2UsageHints: Equatable, Sendable {
    public var root: MultiAgentRoleInstructions?
    public var subagent: MultiAgentRoleInstructions?

    public init(
        root: MultiAgentRoleInstructions? = nil,
        subagent: MultiAgentRoleInstructions? = nil
    ) {
        self.root = root
        self.subagent = subagent
    }
}

public enum MessageDeliveryMode: Equatable, Sendable {
    /// Deliver to the mailbox without starting an idle agent.
    case queueOnly
    /// Deliver to the active turn or start work if the agent is idle.
    case triggerTurn
}

/// Keeps model-provided encrypted content distinct from text that needs a context wrapper.
public enum AgentMessage: Equatable, Sendable {
    case plaintext(String)
    case encrypted(String)

    public var isEmpty: Bool {
        switch self {
        case .plaintext(let text):
            return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .encrypted(let text):
            return text.isEmpty
        }
    }
}

/// Holds a backend-owned reservation until the turn ends or is cancelled.
public final class AgentExecutionGuard: @unchecked Sendable {
    private let permit: Any

    public init(permit: Any = ()) {
        self.permit = permit
    }
}
