//
//  canonicalizer.swift
//  CodexThreadStore
//
//  Port of codex-rs/thread-store/src/local/rollout_migration/canonicalizer.rs
//  (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Writes canonical paginated JSONL through FileHandle. `TurnStartedEvent`
//  / `TurnCompleteEvent` are the current protocol subset (no started_at /
//  completed_at fields). EventMsg `TurnAborted` is unported and is treated
//  as a generic persisted event.
//

import CodexHistory
import CodexProtocol
import CodexRollout
import Foundation

private struct ActiveTurn {
    var id: String
    var explicit: Bool
    var sawUser: Bool
}

private enum ReasoningTextKind {
    case summary
    case raw
}

public struct LegacyRolloutCanonicalizer {
    private let threadId: ThreadId
    private(set) var nextOrdinal: UInt64 = 0
    private var nextItemIndex: UInt64 = 1
    private(set) var outputByteOffset: UInt64 = 0
    private var bytesWritten: UInt64 = 0
    private var sourceLineIndex: UInt64 = 0
    private var activeTurn: ActiveTurn?
    private var knownTurnIds: Set<String> = []
    private var reasoning: ReasoningItem?

    public init(threadId: ThreadId) {
        self.threadId = threadId
    }

    public mutating func writeHeadSessionMeta(_ line: RolloutLine, to handle: FileHandle) throws -> UInt64 {
        let timestamp = line.timestamp
        guard case .sessionMeta(var metadata) = line.item else {
            throw migrationError("canonical session metadata is missing")
        }
        if metadata.meta.id != threadId {
            throw migrationError("rollout metadata thread id changed")
        }
        metadata.meta.historyMode = .paginated
        metadata.meta.historyBase = nil
        metadata.meta.subagentHistoryStartOrdinal = nil
        let bytesBefore = bytesWritten
        try writeItem(handle, timestamp: timestamp, item: .sessionMeta(metadata))
        return bytesWritten - bytesBefore
    }

    mutating func processLine(_ line: RolloutLine, to handle: FileHandle) throws -> UInt64 {
        let sourceIndex = sourceLineIndex
        guard let next = sourceLineIndex.checkedAdd(1) else {
            throw migrationError("legacy rollout line index overflow")
        }
        sourceLineIndex = next
        let timestamp = line.timestamp
        let bytesBefore = bytesWritten
        switch line.item {
        case .sessionMeta:
            return 0
        case .responseItem(let response):
            if case .other = response.item {
                throw migrationError("legacy rollout contains an unsupported response item")
            }
            let hook: HookPromptItem?
            if case .message(let id, let role, let content, _, _) = response.item, role == "user" {
                hook = parseHookPromptMessage(id: id?.asStr, content: content)
            } else {
                hook = nil
            }
            try writeItem(handle, timestamp: timestamp, item: .responseItem(response))
            if let hook {
                try ensureTurn(handle, timestamp: timestamp, sourceIndex: sourceIndex)
                reasoning = nil
                try writeCompletedItem(handle, timestamp: timestamp, item: .hookPrompt(hook))
            }
        case .eventMsg(.threadRolledBack):
            throw migrationError(
                "rollback marker reached canonical writer without a rollback plan")
        case .eventMsg(.turnStarted(let event)):
            try finishImplicitTurn(handle, timestamp: timestamp)
            knownTurnIds.insert(event.turnId)
            activeTurn = ActiveTurn(id: event.turnId, explicit: true, sawUser: false)
            reasoning = nil
            try writeItem(handle, timestamp: timestamp, item: .eventMsg(.turnStarted(event)))
        case .eventMsg(.turnComplete(let event)):
            reasoning = nil
            if activeTurn?.id == event.turnId {
                activeTurn = nil
            }
            try writeItem(handle, timestamp: timestamp, item: .eventMsg(.turnComplete(event)))
        case .eventMsg(.userMessage(let event)):
            if let turn = activeTurn, !turn.explicit && turn.sawUser {
                try finishImplicitTurn(handle, timestamp: timestamp)
            }
            try ensureTurn(handle, timestamp: timestamp, sourceIndex: sourceIndex)
            let item = try userMessageItem(event) { try nextItemId() }
            activeTurn?.sawUser = true
            reasoning = nil
            try writeCompletedItem(handle, timestamp: timestamp, item: item)
        case .eventMsg(.agentReasoning(let event)):
            try writeReasoning(
                handle, timestamp: timestamp, sourceIndex: sourceIndex,
                text: event.text, kind: .summary)
        case .eventMsg(.agentReasoningRawContent(let event)):
            try writeReasoning(
                handle, timestamp: timestamp, sourceIndex: sourceIndex,
                text: event.text, kind: .raw)
        case .eventMsg(.itemCompleted(var event)):
            event.threadId = threadId
            reasoning = nil
            try writeItem(handle, timestamp: timestamp, item: .eventMsg(.itemCompleted(event)))
        case .eventMsg(let event):
            if let (item, turnId) = try completedItem(event, nextItemId: { try nextItemId() }) {
                if let turnId, activeTurn.map({ $0.id != turnId }) == true {
                    try writeCompletedItemToTurn(
                        handle, timestamp: timestamp, turnId: turnId, item: item)
                } else if let turnId, activeTurn == nil, knownTurnIds.contains(turnId) {
                    reasoning = nil
                    try writeCompletedItemToTurn(
                        handle, timestamp: timestamp, turnId: turnId, item: item)
                } else if let turnId, activeTurn == nil {
                    try startImplicitTurn(handle, timestamp: timestamp, turnId: turnId)
                    reasoning = nil
                    try writeCompletedItem(handle, timestamp: timestamp, item: item)
                } else {
                    reasoning = nil
                    try writeCompletedItem(handle, timestamp: timestamp, item: item)
                }
            } else {
                let item = RolloutItem.eventMsg(event)
                if isPersistedRolloutItem(item, historyMode: .paginated) {
                    try writeItem(handle, timestamp: timestamp, item: item)
                }
            }
        case .interAgentCommunication, .compacted, .interAgentCommunicationMetadata,
             .turnContext, .tokenUsageRecord, .realtimeItem, .retainedContext,
             .securityRiskScore, .worldState:
            try writeItem(handle, timestamp: timestamp, item: line.item)
        }
        return bytesWritten - bytesBefore
    }

    mutating func finish(_ handle: FileHandle, timestamp: String) throws -> UInt64 {
        let bytesBefore = bytesWritten
        try finishImplicitTurn(handle, timestamp: timestamp)
        return bytesWritten - bytesBefore
    }

    private mutating func ensureTurn(
        _ handle: FileHandle,
        timestamp: String,
        sourceIndex: UInt64
    ) throws {
        if activeTurn != nil { return }
        try startImplicitTurn(handle, timestamp: timestamp, turnId: "rollout-\(sourceIndex)")
    }

    private mutating func startImplicitTurn(
        _ handle: FileHandle,
        timestamp: String,
        turnId: String
    ) throws {
        activeTurn = ActiveTurn(id: turnId, explicit: false, sawUser: false)
        knownTurnIds.insert(turnId)
        reasoning = nil
        try writeItem(
            handle,
            timestamp: timestamp,
            item: .eventMsg(.turnStarted(TurnStartedEvent(turnId: turnId)))
        )
    }

    private mutating func finishImplicitTurn(_ handle: FileHandle, timestamp: String) throws {
        guard let turn = activeTurn else { return }
        if turn.explicit { return }
        let turnId = turn.id
        activeTurn = nil
        reasoning = nil
        try writeItem(
            handle,
            timestamp: timestamp,
            item: .eventMsg(.turnComplete(TurnCompleteEvent(turnId: turnId)))
        )
    }

    private mutating func writeCompletedItem(
        _ handle: FileHandle,
        timestamp: String,
        item: TurnItem
    ) throws {
        guard let turnId = activeTurn?.id else {
            throw migrationError("completed rollout item has no active turn")
        }
        try writeCompletedItemToTurn(handle, timestamp: timestamp, turnId: turnId, item: item)
    }

    private mutating func writeCompletedItemToTurn(
        _ handle: FileHandle,
        timestamp: String,
        turnId: String,
        item: TurnItem
    ) throws {
        let completedAtMs: Int64
        if let date = parseRfc3339Timestamp(timestamp) {
            completedAtMs = Int64((date.timeIntervalSince1970 * 1000).rounded(.towardZero))
        } else {
            throw migrationError("invalid rfc3339 timestamp")
        }
        try writeItem(
            handle,
            timestamp: timestamp,
            item: .eventMsg(.itemCompleted(ItemCompletedEvent(
                threadId: threadId,
                turnId: turnId,
                item: item,
                startedAtMs: nil,
                completedAtMs: completedAtMs
            )))
        )
    }

    private mutating func writeReasoning(
        _ handle: FileHandle,
        timestamp: String,
        sourceIndex: UInt64,
        text: String,
        kind: ReasoningTextKind
    ) throws {
        if text.isEmpty { return }
        try ensureTurn(handle, timestamp: timestamp, sourceIndex: sourceIndex)
        var item: ReasoningItem
        if let existing = reasoning {
            item = existing
        } else {
            item = ReasoningItem(id: try nextItemId(), summaryText: [], rawContent: [])
        }
        switch kind {
        case .summary: item.summaryText.append(text)
        case .raw: item.rawContent.append(text)
        }
        reasoning = item
        try writeCompletedItem(handle, timestamp: timestamp, item: .reasoning(item))
    }

    private mutating func writeItem(
        _ handle: FileHandle,
        timestamp: String,
        item: RolloutItem
    ) throws {
        let encoded: Data
        do {
            encoded = Data(try encodeRolloutLineString(
                RolloutLine(timestamp: timestamp, ordinal: nextOrdinal, item: item)
            ).utf8) + Data([UInt8(ascii: "\n")])
        } catch {
            throw migrationError(error)
        }
        do {
            try handle.write(contentsOf: encoded)
        } catch {
            throw migrationError(error)
        }
        let byteCount = UInt64(encoded.count)
        guard let nextOffset = outputByteOffset.checkedAdd(byteCount) else {
            throw migrationError("paginated rollout byte offset overflow")
        }
        guard let nextWritten = bytesWritten.checkedAdd(byteCount) else {
            throw migrationError("paginated rollout byte count overflow")
        }
        guard let nextOrd = nextOrdinal.checkedAdd(1) else {
            throw migrationError("paginated rollout ordinal overflow")
        }
        outputByteOffset = nextOffset
        bytesWritten = nextWritten
        nextOrdinal = nextOrd
    }

    private mutating func nextItemId() throws -> String {
        let itemId = "item-\(nextItemIndex)"
        guard let next = nextItemIndex.checkedAdd(1) else {
            throw migrationError("legacy rollout item id overflow")
        }
        nextItemIndex = next
        return itemId
    }
}

private extension UInt64 {
    func checkedAdd(_ other: UInt64) -> UInt64? {
        let (result, overflow) = addingReportingOverflow(other)
        return overflow ? nil : result
    }
}
