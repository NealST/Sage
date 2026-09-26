//
//  rollback_plan.swift
//  CodexThreadStore
//
//  Port of codex-rs/thread-store/src/local/rollout_migration/rollback_plan.rs
//  (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Boundary ownership and replacement-history cut match the Rust planner.
//  Typed `RetainedContextEvent` rollback is omitted because retained context
//  is still `JSONValue` in CodexHistory. EventMsg `TurnAborted` is unported.
//

import CodexHistory
import CodexProtocol
import Foundation

private struct CompactionFrame {
    var recordIndex: Int
    var boundaryDepth: Int
    var owner: Int?
    var item: CompactedItem
}

private struct PendingUserResponse {
    var boundary: Int
    var content: [ContentItem]
}

private struct InstructionBoundary {
    var recordIndex: Int
    var messageId: ResponseItemId?
    var alive: Bool
}

struct RollbackPlan {
    var recordBoundaries: [Int?]
    var boundaryAlive: [Bool]
    var compactedItems: [Int: CompactedItem]

    func recordCount() -> Int { recordBoundaries.count }

    func apply(recordIndex: Int, line: RolloutLine) throws -> RolloutLine? {
        guard recordIndex < recordBoundaries.count else {
            throw migrationError("rollback plan is shorter than source replay")
        }
        if case .eventMsg(.threadRolledBack) = line.item {
            return nil
        }
        if let compacted = compactedItems[recordIndex] {
            var line = line
            line.item = .compacted(compacted)
            return line
        }
        if let boundary = recordBoundaries[recordIndex], !boundaryAlive[boundary] {
            return nil
        }
        return line
    }
}

struct RollbackPlanner {
    private var recordBoundaries: [Int?] = []
    private var boundaries: [InstructionBoundary] = []
    private var boundaryStack: [Int] = []
    private var activeTurnId: String?
    private var pendingTurnRecords: [Int] = []
    private var pendingContextRecords: [Int] = []
    private var pendingUserResponse: PendingUserResponse?
    private var pendingDeliveryBoundary: Int?
    private var turnBoundaries: [String: Int] = [:]
    private var callBoundaries: [String: Int?] = [:]
    private var compactions: [CompactionFrame] = []
    private var modelReplay = ModelReplayPlanner()

    init() {}

    mutating func observe(_ line: RolloutLine) throws {
        let index = recordBoundaries.count
        modelReplay.observe(recordIndex: index, item: line.item)
        recordBoundaries.append(boundaryStack.last)
        let pairedUserBoundary: Int?
        if let pending = pendingUserResponse,
           case .eventMsg(.userMessage(let event)) = line.item,
           userResponseMatchesEvent(pending.content, event)
        {
            pairedUserBoundary = pending.boundary
        } else {
            pairedUserBoundary = nil
        }
        let pairedDeliveryBoundary: Int?
        if let boundary = pendingDeliveryBoundary,
           case .responseItem(let response) = line.item,
           case .agentMessage = response.item
        {
            pairedDeliveryBoundary = boundary
        } else {
            pairedDeliveryBoundary = nil
        }
        pendingUserResponse = nil
        pendingDeliveryBoundary = nil

        switch line.item {
        case .sessionMeta:
            recordBoundaries[index] = nil
        case .responseItem(let response):
            if let boundary = pairedDeliveryBoundary {
                recordBoundaries[index] = boundary
                boundaries[boundary].messageId = responseItemId(response.item)
            } else if countsAsBoundary(response.item) {
                let boundary = startBoundary(index)
                boundaries[boundary].messageId = responseItemId(response.item)
                if case .message(_, let role, let content, _, _) = response.item, role == "user" {
                    pendingUserResponse = PendingUserResponse(boundary: boundary, content: content)
                }
            } else if isPreTurnContextUpdate(response.item) {
                pendingContextRecords.append(index)
            }
            if case .functionCall(_, _, _, _, _, let callId, _) = response.item {
                let turnId = activeTurnId ?? ""
                callBoundaries["\(turnId)\0\(callId)"] = recordBoundaries[index]
            }
        case .eventMsg(.threadRolledBack(let rollback)):
            try applyRollback(rollback.numTurns)
        case .eventMsg(.turnStarted(let event)):
            activeTurnId = event.turnId
            pendingTurnRecords = [index]
        case .eventMsg(.turnComplete(let event)):
            assignTargetedRecord(index, event.turnId)
            if activeTurnId == event.turnId {
                activeTurnId = nil
                pendingTurnRecords.removeAll()
            }
        case .eventMsg(.userMessage):
            let boundary = pairedUserBoundary ?? startBoundary(index)
            recordBoundaries[index] = boundary
        case .eventMsg(.itemCompleted(let event)):
            assignTargetedRecord(index, event.turnId)
        case .eventMsg(let event):
            assignTargetedRecord(index, explicitEventTurnId(event))
        case .interAgentCommunication:
            _ = startBoundary(index)
        case .interAgentCommunicationMetadata:
            pendingDeliveryBoundary = startBoundary(index)
        case .compacted(let item):
            let owner = activeTurnId.flatMap { turnBoundaries[$0] }
            recordBoundaries[index] = owner
            compactions.append(CompactionFrame(
                recordIndex: index,
                boundaryDepth: boundaryStack.count,
                owner: owner,
                item: item
            ))
        case .turnContext:
            if let turnId = activeTurnId, turnBoundaries[turnId] == nil {
                pendingTurnRecords.append(index)
            }
        case .tokenUsageRecord(let record):
            assignTargetedRecord(index, record.turnId)
        case .worldState, .realtimeItem, .retainedContext, .securityRiskScore:
            if case .securityRiskScore = line.item {
                recordBoundaries[index] = nil
            }
        }
    }

    func finish() -> RollbackPlan {
        let replayAnchor = modelReplay.finish().emptyReplacementHistoryCompaction
        let boundaryAlive = boundaries.map(\.alive)
        var compactedItems: [Int: CompactedItem] = [:]
        for var frame in compactions {
            if frame.recordIndex == replayAnchor {
                frame.item.replacementHistory = []
                frame.item.mcpResourceOrigins = nil
                compactedItems[frame.recordIndex] = frame.item
                continue
            }
            if frame.owner.map({ boundaryAlive[$0] }) ?? true {
                compactedItems[frame.recordIndex] = frame.item
            }
        }
        return RollbackPlan(
            recordBoundaries: recordBoundaries,
            boundaryAlive: boundaryAlive,
            compactedItems: compactedItems
        )
    }

    private mutating func startBoundary(_ index: Int) -> Int {
        let boundary = boundaries.count
        boundaries.append(InstructionBoundary(recordIndex: index, messageId: nil, alive: true))
        let hadPriorBoundary = !boundaryStack.isEmpty
        if hadPriorBoundary {
            for pendingIndex in pendingContextRecords {
                recordBoundaries[pendingIndex] = boundary
            }
            pendingContextRecords.removeAll()
        } else {
            pendingContextRecords.removeAll()
        }
        for pendingIndex in pendingTurnRecords {
            recordBoundaries[pendingIndex] = boundary
        }
        pendingTurnRecords.removeAll()
        recordBoundaries[index] = boundary
        boundaryStack.append(boundary)
        bindActiveTurn(boundary)
        return boundary
    }

    private mutating func bindActiveTurn(_ boundary: Int) {
        if let turnId = activeTurnId {
            turnBoundaries[turnId] = boundary
        }
    }

    private mutating func assignTargetedRecord(_ index: Int, _ turnId: String?) {
        if let turnId, let boundary = turnBoundaries[turnId] {
            recordBoundaries[index] = boundary
        } else if let turnId = activeTurnId, turnBoundaries[turnId] == nil {
            pendingTurnRecords.append(index)
        } else if activeTurnId != nil, activeTurnId.flatMap({ turnBoundaries[$0] }) == nil {
            pendingTurnRecords.append(index)
        }
    }

    private mutating func applyRollback(_ numTurns: UInt32) throws {
        let count = Int(exactly: numTurns) ?? Int.max
        if count == 0 { return }
        let depthBefore = boundaryStack.count
        var removedBoundaries = Set<Int>()
        var firstRemoved: InstructionBoundary?
        for _ in 0..<count {
            guard let boundary = boundaryStack.popLast() else { break }
            boundaries[boundary].alive = false
            removedBoundaries.insert(boundary)
            firstRemoved = boundaries[boundary]
        }
        let compactionIndex = compactions.lastIndex { frame in
            frame.owner.map { boundaries[$0].alive } ?? true
        }
        if let compactionIndex, let source = firstRemoved {
            let frame = compactions[compactionIndex]
            let postCompactionTurns = depthBefore - frame.boundaryDepth
            let remaining = count - postCompactionTurns
            if remaining > 0 {
                if compactions[compactionIndex].item.replacementHistory == nil {
                    throw migrationError(
                        "legacy rollback crosses a compaction without replacement history")
                }
                dropLastNUserTurns(
                    &compactions[compactionIndex].item.replacementHistory!,
                    numTurns: UInt32(clamping: remaining)
                )
                _ = source
            }
        }
        activeTurnId = nil
        pendingTurnRecords.removeAll()
        pendingContextRecords.removeAll()
        pendingUserResponse = nil
        pendingDeliveryBoundary = nil
        _ = removedBoundaries
    }
}

private func explicitEventTurnId(_ event: EventMsg) -> String? {
    let turnId: String?
    switch event {
    case .execCommandEnd(let event): turnId = event.turnId
    case .patchApplyEnd(let event): turnId = event.turnId
    case .dynamicToolCallResponse(let event): turnId = event.turnId
    case .enteredReviewMode(let event): turnId = event.turnId
    case .exitedReviewMode(let event): turnId = event.turnId
    default: turnId = nil
    }
    guard let turnId, !turnId.isEmpty else { return nil }
    return turnId
}

private func responseItemId(_ item: ResponseItem) -> ResponseItemId? {
    switch item {
    case .message(let id, _, _, _, _),
         .agentMessage(let id, _, _, _, _),
         .functionCall(let id, _, _, _, _, _, _):
        return id
    default:
        return nil
    }
}

private func userResponseMatchesEvent(_ content: [ContentItem], _ event: UserMessageEvent) -> Bool {
    var text = ""
    var images: [String] = []
    var fileIds: [String] = []
    var imageOrder: [UserMessageImageKind] = []
    var audio: [String] = []
    for item in content {
        switch item {
        case .inputText(let itemText):
            text += itemText
        case .inputImage(let image, _):
            switch image {
            case .inline(let imageUrl):
                imageOrder.append(.inline)
                images.append(imageUrl)
            case .file(let fileId):
                imageOrder.append(.file)
                fileIds.append(fileId)
            }
        case .inputAudio(let audioUrl):
            audio.append(audioUrl)
        case .outputText:
            return false
        }
    }
    return text == event.message
        && (!event.hasCompleteImageOrder() || imageOrder == event.imageOrder)
        && images == (event.images ?? [])
        && fileIds == (event.fileIds ?? [])
        && audio == (event.audio ?? [])
        && event.localImages.isEmpty
        && event.localAudio.isEmpty
}
