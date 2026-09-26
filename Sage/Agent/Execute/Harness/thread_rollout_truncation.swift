//
//  thread_rollout_truncation.swift
//  CodexCore
//
//  Port of codex-rs/core/src/thread_rollout_truncation.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  `parse_turn_item` is still identity, so user-message detection uses
//  `ResponseItem.isUserMessage()`. `build_turns_from_rollout_items` (app-server)
//  is omitted; after/before-turn-id cuts look at persisted `TurnStarted`.
//  `InterAgentCommunication::from_message_content` is not ported.
//

import CodexHistory
import CodexProtocol
import Foundation

public func initialHistoryHasPriorUserTurns(_ conversationHistory: InitialHistory) -> Bool {
    conversationHistory.scanRolloutItems(rolloutItemIsUserTurnBoundary)
}

func rolloutItemIsUserTurnBoundary(_ item: RolloutItem) -> Bool {
    switch item {
    case .responseItem(let envelope):
        return isUserTurnBoundary(envelope.item)
    case .compacted(let checkpoint):
        return (checkpoint.replacementHistory ?? []).contains { isUserTurnBoundary($0.item) }
    case .interAgentCommunication:
        return true
    default:
        return false
    }
}

/// Return the indices of user message boundaries in a rollout.
public func userMessagePositionsInRollout(_ items: [RolloutItem]) -> [Int] {
    var userPositions: [Int] = []
    for (idx, item) in items.enumerated() {
        switch item {
        case .responseItem(let envelope)
            where envelope.item.isUserMessage()
                && {
                    if case .userMessage = parseTurnItemAsTurn(envelope.item) { return true }
                    return envelope.item.isUserMessage()
                }():
            userPositions.append(idx)
        case .eventMsg(.threadRolledBack(let rollback)):
            let numTurns = Int(rollback.numTurns)
            userPositions = Array(userPositions.prefix(max(0, userPositions.count - numTurns)))
        default:
            break
        }
    }
    return userPositions
}

/// Return the indices of fork-turn boundaries in a rollout.
public func forkTurnPositionsInRollout(_ items: [RolloutItem]) -> [Int] {
    var rollbackTurnPositions: [Int] = []
    var forkTurnPositions: [Int] = []
    for (idx, item) in items.enumerated() {
        switch item {
        case .responseItem(let envelope):
            let hasDeliveryMetadata: Bool = {
                if case .agentMessage = envelope.item, idx > 0 {
                    if case .interAgentCommunicationMetadata = items[idx - 1] { return true }
                }
                return false
            }()
            if isUserTurnBoundary(envelope.item) && !hasDeliveryMetadata {
                rollbackTurnPositions.append(idx)
            }
            if isRealUserMessageBoundary(envelope.item) || isTriggerTurnBoundary(envelope.item) {
                forkTurnPositions.append(idx)
            }
        case .interAgentCommunication(let communication):
            rollbackTurnPositions.append(idx)
            if communication.triggerTurn {
                forkTurnPositions.append(idx)
            }
        case .interAgentCommunicationMetadata(let triggerTurn):
            rollbackTurnPositions.append(idx)
            if triggerTurn {
                forkTurnPositions.append(idx)
            }
        case .eventMsg(.threadRolledBack(let rollback)):
            let numTurns = Int(rollback.numTurns)
            if numTurns == 0 { continue }
            let rollbackStartIdx: Int
            if rollbackTurnPositions.count >= numTurns {
                rollbackStartIdx = rollbackTurnPositions[rollbackTurnPositions.count - numTurns]
            } else if let first = rollbackTurnPositions.first {
                rollbackStartIdx = first
            } else {
                continue
            }
            rollbackTurnPositions = Array(
                rollbackTurnPositions.prefix(max(0, rollbackTurnPositions.count - numTurns)))
            forkTurnPositions.removeAll { $0 >= rollbackStartIdx }
        default:
            break
        }
    }
    return forkTurnPositions
}

public func truncateRolloutBeforeNthUserMessageFromStart(
    _ items: [RolloutItem],
    nFromStart: Int
) -> [RolloutItem] {
    if nFromStart == Int.max { return items }
    let userPositions = userMessagePositionsInRollout(items)
    if userPositions.count <= nFromStart { return items }
    return Array(items.prefix(userPositions[nFromStart]))
}

public func truncateRolloutAfterTurnId(
    _ items: [RolloutItem],
    lastTurnId: String
) throws -> [RolloutItem] {
    guard let targetStartIndex = items.firstIndex(where: {
        if case .eventMsg(.turnStarted(let event)) = $0 { return event.turnId == lastTurnId }
        return false
    }) else {
        throw CodexErr.invalidRequest(
            "lastTurnId '\(lastTurnId)' was not found in the source thread")
    }
    let cutIndex = items[(targetStartIndex + 1)...].firstIndex(where: {
        if case .eventMsg(.turnStarted) = $0 { return true }
        return false
    }) ?? items.endIndex
    return Array(items.prefix(cutIndex))
}

public func truncateRolloutBeforeTurnId(
    _ items: [RolloutItem],
    beforeTurnId: String
) throws -> [RolloutItem] {
    guard let cutIndex = items.firstIndex(where: {
        if case .eventMsg(.turnStarted(let event)) = $0 { return event.turnId == beforeTurnId }
        return false
    }) else {
        throw CodexErr.invalidRequest(
            "beforeTurnId '\(beforeTurnId)' was not found in the source thread")
    }
    return Array(items.prefix(cutIndex))
}

public func truncateRolloutToLastNForkTurns(
    _ items: [RolloutItem],
    nFromEnd: Int
) -> [RolloutItem] {
    if nFromEnd == 0 { return [] }
    let forkTurnPositions = forkTurnPositionsInRollout(items)
    let keepIdx: Int
    if forkTurnPositions.count >= nFromEnd {
        keepIdx = forkTurnPositions[forkTurnPositions.count - nFromEnd]
    } else if let first = forkTurnPositions.first {
        keepIdx = first
    } else {
        return []
    }
    return Array(items.suffix(from: keepIdx))
}

private func isRealUserMessageBoundary(_ item: ResponseItem) -> Bool {
    item.isUserMessage()
}

private func isTriggerTurnBoundary(_ item: ResponseItem) -> Bool {
    false
}

/// `parse_turn_item` is identity today; keep a hook for when it returns `TurnItem`.
private func parseTurnItemAsTurn(_ item: ResponseItem) -> TurnItem? {
    _ = parseTurnItem(item)
    return nil
}
