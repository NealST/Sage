//
//  control_spawn.swift
//  CodexCore
//
//  Port of codex-rs/core/src/agent/control/spawn.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Nickname candidates, forked-history filters, and metadata reservation
//  are faithful. Spawn copies parent CodexThread history when fork_mode is
//  set and a ThreadManager is attached, then submits the child's initial
//  user input through ThreadSession. Rollout restore stays deferred.
//  R4a: basename `spawn.swift` already belongs to core/src/spawn.rs.
//

import CodexAgentRoles
import CodexHistory
import CodexProtocol
import Foundation

let AGENT_NAMES = """
Euclid
Archimedes
Ptolemy
Hypatia
Avicenna
Averroes
Aquinas
Copernicus
Kepler
Galileo
Bacon
Descartes
Pascal
Fermat
Huygens
Leibniz
Newton
Halley
Euler
Lagrange
Laplace
Volta
Gauss
Ampere
Faraday
Darwin
Lovelace
Boole
Pasteur
Maxwell
Mendel
Curie
Planck
Tesla
Poincare
Noether
Hilbert
Einstein
Raman
Bohr
Turing
Hubble
Feynman
Franklin
McClintock
Meitner
Herschel
Linnaeus
Wegener
Chandrasekhar
Sagan
Goodall
Carson
Carver
Socrates
Plato
Aristotle
Epicurus
Cicero
Confucius
Mencius
Zeno
Locke
Hume
Kant
Hegel
Kierkegaard
Mill
Nietzsche
Peirce
James
Dewey
Russell
Popper
Sartre
Beauvoir
Arendt
Rawls
Singer
Anscombe
Parfit
Kuhn
Boyle
Hooke
Harvey
Dalton
Ohm
Helmholtz
Gibbs
Lorentz
Schrodinger
Heisenberg
Pauli
Dirac
Bernoulli
Godel
Nash
Banach
Ramanujan
Erdos
Jason
"""

/// Initial input delivered after a spawned agent acquires execution capacity.
public enum SpawnInitialInput: Equatable, Sendable {
    case userInput([UserInput])
    case interAgentCommunication(InterAgentCommunication)
}

public func defaultAgentNicknameList() -> [String] {
    AGENT_NAMES
        .split(whereSeparator: \.isNewline)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
}

public func agentNicknameCandidates(
    roleName: String? = nil,
    userDefined: [String: AgentRoleConfig] = [:]
) -> [String] {
    let roleName = roleName ?? DEFAULT_ROLE_NAME
    if let candidates = resolveRoleConfig(roleName: roleName, userDefined: userDefined)?
        .nicknameCandidates
    {
        return candidates
    }
    return defaultAgentNicknameList()
}

public func preserveContextBaselinesForFork(
    _ items: [RolloutItem],
    forkMode: SpawnAgentForkMode
) -> Bool {
    guard forkMode == .fullHistory else { return false }
    for item in items.reversed() {
        if case .compacted(let compacted) = item {
            return compacted.replacementHistory != nil
        }
    }
    return true
}

public func filterForkedRolloutItems(
    _ items: [RolloutItem],
    forkMode: SpawnAgentForkMode
) -> [RolloutItem] {
    var items = items
    if case .lastNTurns(let n) = forkMode {
        items = truncateRolloutToLastNForkTurns(items, nFromEnd: n)
    }
    let preserve = preserveContextBaselinesForFork(items, forkMode: forkMode)
    return items.filter { keepForkedRolloutItem($0, preserveContextBaselines: preserve) }
}

func spawnForkParentThreadId(
    _ request: SpawnRequest,
    sessionSource: SessionSource
) throws -> ThreadId? {
    guard request.options.forkMode != nil else { return nil }
    guard request.options.forkParentSpawnCallId != nil else {
        throw CodexErr.fatal("spawn_agent fork requires a parent spawn call id")
    }
    guard case .subAgent(.threadSpawn(let parentThreadId, _, _, _, _)) = sessionSource else {
        throw CodexErr.fatal("spawn_agent fork requires a thread-spawn session source")
    }
    return parentThreadId
}

func copySpawnForkHistory(
    forkMode: SpawnAgentForkMode,
    parentThreadId: ThreadId,
    childThreadId: ThreadId,
    manager: ThreadManager
) {
    let parentItems = manager.peekThread(parentThreadId)?.historyItems() ?? []
    let filtered = filterForkedRolloutItems(parentItems, forkMode: forkMode)
    let forked = forkHistoryItems(filtered, snapshot: .interrupted)
    manager.peekThread(childThreadId)?.replaceHistory(forked)
}

public func keepForkedRolloutItem(
    _ item: RolloutItem,
    preserveContextBaselines: Bool
) -> Bool {
    switch item {
    case .responseItem(let envelope):
        switch envelope.item {
        case .message(_, let role, _, let phase, _):
            switch role {
            case "system", "developer", "user":
                return true
            case "assistant":
                return phase == .finalAnswer
            default:
                return false
            }
        case .functionCallOutput(_, let callId, _, _, _, _):
            return callId == nil
        case .configurationUpdate:
            return true
        case .additionalTools, .agentMessage, .reasoning, .localShellCall, .functionCall,
             .toolSearchCall, .customToolCall, .customToolCallOutput, .toolSearchOutput,
             .webSearchCall, .imageGenerationCall, .compaction, .compactionTrigger,
             .contextCompaction, .other:
            return false
        }
    case .realtimeItem, .interAgentCommunication, .interAgentCommunicationMetadata,
         .retainedContext, .securityRiskScore:
        return false
    case .turnContext, .worldState:
        return preserveContextBaselines
    case .tokenUsageRecord:
        return false
    case .compacted, .eventMsg, .sessionMeta:
        return true
    }
}

let autoReviewDeniedActionApprovalDeveloperPrefix =
    "The user has manually approved a specific action that was previously `Rejected`."

public func retainForkedDeveloperMessage(
    _ item: inout ResponseItem,
    usageHintTexts: [String]
) -> Bool {
    guard case .message(_, let role, _, _, _) = item, role == "developer" else {
        return true
    }
    guard var content = toAnnotatedContent(&item) else {
        return false
    }
    content.removeAll { contentItem in
        if contentItem.kind.value == "guardian.approved_action" {
            return true
        }
        guard case .inputText(let text) = contentItem.content else {
            return false
        }
        return MultiAgentRoleInstructions.matchesText(text)
            || text.hasPrefix(autoReviewDeniedActionApprovalDeveloperPrefix)
            || MultiAgentModeInstructions(text: "").matchesText(text)
            || CurrentTimeReminder(currentTime: Date()).matchesText(text)
            || CurrentTimeUnavailable().matchesText(text)
            || usageHintTexts.contains(text)
    }
    return !content.isEmpty && setAnnotatedContent(&item, content)
}

extension LocalAgentControl {
    public func restoreV2AgentMetadata(rootThreadId: ThreadId) async {
        runtime.registry.registerRootThread(rootThreadId)
    }

    public func prepareAgentMetadata(
        reservation: SpawnReservation,
        agentPath: AgentPath?,
        agentRole: String?,
        preferredAgentNickname: String?,
        userDefinedRoles: [String: AgentRoleConfig] = [:]
    ) throws -> AgentMetadata {
        if let agentPath {
            try reservation.reserveAgentPath(agentPath)
        }
        let candidateNames = agentNicknameCandidates(
            roleName: agentRole,
            userDefined: userDefinedRoles
        )
        let agentNickname = try reservation.reserveAgentNicknameWithPreference(
            names: candidateNames,
            preferred: preferredAgentNickname
        )
        return AgentMetadata(
            agentId: nil,
            agentPath: agentPath,
            agentNickname: agentNickname,
            agentRole: agentRole
        )
    }

    public func prepareThreadSpawn(
        reservation: SpawnReservation,
        parentThreadId: ThreadId,
        depth: Int32,
        agentPath: AgentPath?,
        agentRole: String?,
        preferredAgentNickname: String?,
        userDefinedRoles: [String: AgentRoleConfig] = [:]
    ) throws -> (SessionSource, AgentMetadata) {
        if depth == 1 {
            runtime.registry.registerRootThread(parentThreadId)
        }
        let agentMetadata = try prepareAgentMetadata(
            reservation: reservation,
            agentPath: agentPath,
            agentRole: agentRole,
            preferredAgentNickname: preferredAgentNickname,
            userDefinedRoles: userDefinedRoles
        )
        let sessionSource = SessionSource.subAgent(
            .threadSpawn(
                parentThreadId: parentThreadId,
                depth: depth,
                agentPath: agentMetadata.agentPath,
                agentNickname: agentMetadata.agentNickname,
                agentRole: agentMetadata.agentRole
            )
        )
        return (sessionSource, agentMetadata)
    }
}
