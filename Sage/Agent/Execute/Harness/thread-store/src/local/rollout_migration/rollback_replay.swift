//
//  rollback_replay.swift
//  CodexThreadStore
//
//  Port of codex-rs/thread-store/src/local/rollout_migration/rollback_replay.rs
//  (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  EventMsg is a subset: `TurnAborted` is unported, so those records are not
//  observed. Other replay records match the Rust planner.
//

import CodexHistory
import CodexProtocol
import Foundation

private enum ReplayRecord {
    case compacted(recordIndex: Int, hasReplacementHistory: Bool)
    case rollback(UInt32)
    case turnStarted(String)
    case turnComplete(String)
    case turnContext(String?)
    case userBoundary
}

private struct ReverseSegment {
    var turnId: String?
    var countsAsUserTurn: Bool = false
    var compactionIndex: Int?
}

struct ModelReplayPlan {
    var emptyReplacementHistoryCompaction: Int?
}

struct ModelReplayPlanner {
    private var records: [ReplayRecord] = []

    init() {}

    mutating func observe(recordIndex: Int, item: RolloutItem) {
        let record: ReplayRecord
        switch item {
        case .compacted(let compacted):
            record = .compacted(
                recordIndex: recordIndex,
                hasReplacementHistory: compacted.replacementHistory != nil)
        case .eventMsg(.threadRolledBack(let rollback)):
            record = .rollback(rollback.numTurns)
        case .eventMsg(.turnStarted(let event)):
            record = .turnStarted(event.turnId)
        case .eventMsg(.turnComplete(let event)):
            record = .turnComplete(event.turnId)
        case .turnContext(let context):
            record = .turnContext(context.turnId)
        case .eventMsg(.userMessage), .interAgentCommunication:
            record = .userBoundary
        case .responseItem(let response) where countsAsBoundary(response.item):
            record = .userBoundary
        default:
            return
        }
        records.append(record)
    }

    func finish() -> ModelReplayPlan {
        var selectedCompaction: Int?
        var suffixStart: Int?
        var pendingRollbackTurns = 0
        var activeSegment: ReverseSegment?

        for record in records.reversed() {
            switch record {
            case .compacted(let recordIndex, let hasReplacementHistory):
                var segment = activeSegment ?? ReverseSegment()
                if segment.compactionIndex == nil && hasReplacementHistory {
                    segment.compactionIndex = recordIndex
                    suffixStart = recordIndex + 1
                }
                activeSegment = segment
            case .rollback(let numTurns):
                let added = Int(exactly: numTurns) ?? Int.max
                if pendingRollbackTurns > Int.max - added {
                    pendingRollbackTurns = Int.max
                } else {
                    pendingRollbackTurns += added
                }
            case .turnComplete(let turnId):
                var segment = activeSegment ?? ReverseSegment()
                if segment.turnId == nil {
                    segment.turnId = turnId
                }
                activeSegment = segment
            case .turnContext(let turnId):
                var segment = activeSegment ?? ReverseSegment()
                if segment.turnId == nil {
                    segment.turnId = turnId
                }
                activeSegment = segment
            case .userBoundary:
                var segment = activeSegment ?? ReverseSegment()
                segment.countsAsUserTurn = true
                activeSegment = segment
            case .turnStarted(let turnId):
                if let segment = activeSegment,
                   turnIdsAreCompatible(segment.turnId, turnId)
                {
                    finalizeSegment(
                        segment,
                        selectedCompaction: &selectedCompaction,
                        pendingRollbackTurns: &pendingRollbackTurns
                    )
                    activeSegment = nil
                }
            }
        }

        if let segment = activeSegment {
            finalizeSegment(
                segment,
                selectedCompaction: &selectedCompaction,
                pendingRollbackTurns: &pendingRollbackTurns
            )
        }

        let emptyReplacementHistoryCompaction: Int?
        if selectedCompaction == nil, let start = suffixStart {
            emptyReplacementHistoryCompaction = start > 0 ? start - 1 : nil
        } else {
            emptyReplacementHistoryCompaction = nil
        }
        return ModelReplayPlan(
            emptyReplacementHistoryCompaction: emptyReplacementHistoryCompaction)
    }
}

private func finalizeSegment(
    _ segment: ReverseSegment,
    selectedCompaction: inout Int?,
    pendingRollbackTurns: inout Int
) {
    if pendingRollbackTurns > 0 {
        if segment.countsAsUserTurn {
            pendingRollbackTurns -= 1
        }
        return
    }
    if selectedCompaction == nil {
        selectedCompaction = segment.compactionIndex
    }
}

private func turnIdsAreCompatible(_ activeTurnId: String?, _ itemTurnId: String?) -> Bool {
    guard let activeTurnId else { return true }
    guard let itemTurnId else { return true }
    return itemTurnId == activeTurnId
}
