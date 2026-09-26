//
//  thread_history_materialization.swift
//  CodexThreadStore
//
//  Port of codex-rs/thread-store/src/local/thread_history_materialization.rs
//  (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  JSONL `readProjectionSteps` is ported (FileHandle / decodeRolloutLine).
//  Persist (`applyProjection`) throws until GRDB. `project_rollout_line` /
//  `ThreadHistoryChangeSet` are unported: `changes` is an empty JSON object
//  and fallback timestamps are computed only for realtime items.
//  OpenTelemetry projection counters are omitted.
//

import CodexHistory
import CodexProtocol
import CodexRollout
import Foundation
import os

private let logger = Logger(
    subsystem: "CodexThreadStore",
    category: "thread_history_materialization")

func materializeToSqlite(
    store: LocalThreadStore,
    threadId: ThreadId,
    rolloutPath: String
) throws {
    if store.stateDb() == nil {
        return
    }
    do {
        try materializeToSqliteWithStateDb(
            store: store,
            threadId: threadId,
            rolloutPath: rolloutPath
        )
        recordProjectionOutcome(success: true)
    } catch {
        recordProjectionOutcome(success: false)
        throw error
    }
}

func materializeToSqliteWithStateDb(
    store: LocalThreadStore,
    threadId: ThreadId,
    rolloutPath: String
) throws {
    let projection = try projectionState(store: store, threadId: threadId)
    let startOffset = projection?.nextByteOffset ?? 0
    if projection == nil, existingRolloutPath(rolloutPath) == nil {
        return
    }
    let sessionMeta: SessionMeta
    do {
        sessionMeta = try readSessionMetaLine(path: rolloutPath).meta
    } catch {
        throw threadStoreIoError(error)
    }
    let initialOrdinal = sessionMeta.historyBase?.endOrdinalExclusive ?? 0
    let expectedOrdinal = projection?.nextOrdinal ?? initialOrdinal
    let (projections, nextOffset) = try readProjectionSteps(
        rolloutPath: rolloutPath,
        startOffset: startOffset,
        expectedOrdinal: expectedOrdinal,
        threadId: threadId,
        subagentHistoryStartOrdinal: sessionMeta.subagentHistoryStartOrdinal
    )
    if projections.isEmpty && startOffset == nextOffset {
        return
    }
    try applyProjection(
        store: store,
        threadId: threadId,
        startOffset: startOffset,
        nextOffset: nextOffset,
        initialOrdinal: initialOrdinal,
        projections: projections
    )
}

func readProjectionSteps(
    rolloutPath: String,
    startOffset: UInt64,
    expectedOrdinal: UInt64,
    threadId: ThreadId,
    subagentHistoryStartOrdinal: UInt64?
) throws -> ([RolloutProjectionStep], UInt64) {
    let handle: FileHandle
    do {
        handle = try openRolloutSeekableReader(path: rolloutPath)
    } catch {
        if startOffset == 0, existingRolloutPath(rolloutPath) == nil {
            return ([], 0)
        }
        throw threadStoreIoError(error)
    }
    defer { try? handle.close() }

    let fileEndOffset: UInt64
    do {
        fileEndOffset = try handle.seekToEnd()
    } catch {
        throw threadStoreIoError(error)
    }
    guard fileEndOffset >= startOffset else {
        throw ThreadStoreError.internal("durable rollout shrank before projection")
    }
    let byteCount64 = fileEndOffset - startOffset
    guard let byteCount = Int(exactly: byteCount64) else {
        throw ThreadStoreError.internal("durable rollout append exceeds addressable memory")
    }
    do {
        try handle.seek(toOffset: startOffset)
    } catch {
        throw threadStoreIoError(error)
    }
    let data: Data
    do {
        data = try handle.read(upToCount: byteCount) ?? Data()
    } catch {
        throw threadStoreIoError(error)
    }
    let bytes = [UInt8](data)
    let completeByteCount = bytes.lastIndex(of: UInt8(ascii: "\n")).map { $0 + 1 } ?? 0

    var projections: [RolloutProjectionStep] = []
    var nextOrdinal = expectedOrdinal
    var nextOffset = startOffset
    var lineStartOffset = startOffset
    var index = 0
    while index < completeByteCount {
        guard let newline = bytes[index..<completeByteCount].firstIndex(of: UInt8(ascii: "\n")) else {
            break
        }
        let lineEnd = newline + 1
        let lineBytes = Data(bytes[index..<lineEnd])
        guard let lineLen = UInt64(exactly: lineBytes.count) else {
            throw ThreadStoreError.internal("durable rollout byte offset overflow")
        }
        let (lineEndOffset, overflow) = lineStartOffset.addingReportingOverflow(lineLen)
        if overflow {
            throw ThreadStoreError.internal("durable rollout byte offset overflow")
        }
        if lineBytes.allSatisfy(isAsciiWhitespace) {
            nextOffset = lineEndOffset
            lineStartOffset = lineEndOffset
            index = lineEnd
            continue
        }

        let value: JSONValue
        do {
            value = try JSONDecoder().decode(JSONValue.self, from: lineBytes)
        } catch {
            logger.warning(
                """
                skipping malformed rollout line during projection \
                thread_id=\(threadId.description, privacy: .public) \
                rollout_path=\(rolloutPath, privacy: .public) \
                line_start_byte_offset=\(lineStartOffset, privacy: .public) \
                line_end_byte_offset=\(lineEndOffset, privacy: .public) \
                expected_ordinal=\(nextOrdinal, privacy: .public) \
                error=\(String(describing: error), privacy: .public)
                """)
            recordProjectionAnomaly(.malformedJson)
            nextOffset = lineEndOffset
            lineStartOffset = lineEndOffset
            index = lineEnd
            continue
        }
        let rawOrdinal = jsonAsUInt64(value.objectValue?["ordinal"])
        let line: RolloutLine
        do {
            line = try decodeRolloutLine(value)
        } catch {
            logger.warning(
                """
                skipping unknown rollout line during projection \
                thread_id=\(threadId.description, privacy: .public) \
                rollout_path=\(rolloutPath, privacy: .public) \
                line_start_byte_offset=\(lineStartOffset, privacy: .public) \
                line_end_byte_offset=\(lineEndOffset, privacy: .public) \
                expected_ordinal=\(nextOrdinal, privacy: .public) \
                line_ordinal=\(String(describing: rawOrdinal), privacy: .public) \
                error=\(String(describing: error), privacy: .public)
                """)
            recordProjectionAnomaly(.unknownLine)
            nextOffset = lineEndOffset
            lineStartOffset = lineEndOffset
            index = lineEnd
            continue
        }
        guard let ordinal = line.ordinal else {
            logger.warning(
                """
                skipping paginated rollout line without an ordinal \
                thread_id=\(threadId.description, privacy: .public) \
                rollout_path=\(rolloutPath, privacy: .public) \
                line_start_byte_offset=\(lineStartOffset, privacy: .public) \
                line_end_byte_offset=\(lineEndOffset, privacy: .public) \
                expected_ordinal=\(nextOrdinal, privacy: .public)
                """)
            recordProjectionAnomaly(.missingOrdinal)
            nextOffset = lineEndOffset
            lineStartOffset = lineEndOffset
            index = lineEnd
            continue
        }
        if ordinal < nextOrdinal {
            logger.warning(
                """
                skipping duplicate or regressed rollout ordinal during projection \
                thread_id=\(threadId.description, privacy: .public) \
                rollout_path=\(rolloutPath, privacy: .public) \
                line_start_byte_offset=\(lineStartOffset, privacy: .public) \
                line_end_byte_offset=\(lineEndOffset, privacy: .public) \
                expected_ordinal=\(nextOrdinal, privacy: .public) \
                line_ordinal=\(ordinal, privacy: .public)
                """)
            recordProjectionAnomaly(.duplicateOrRegressedOrdinal)
            nextOffset = lineEndOffset
            lineStartOffset = lineEndOffset
            index = lineEnd
            continue
        }

        let isInheritedSubagentHistory =
            subagentHistoryStartOrdinal.map { ordinal < $0 } ?? false
        // `project_rollout_line` / ThreadHistoryChangeSet are unported.
        let changes = JSONValue.object([:])
        let needsFallbackTimestamp: Bool = {
            if isInheritedSubagentHistory { return false }
            if case .realtimeItem = line.item { return true }
            return false
        }()
        let fallbackCreatedAtMs: Int64?
        if needsFallbackTimestamp {
            if let millis = rfc3339TimestampMillis(line.timestamp) {
                fallbackCreatedAtMs = millis
            } else {
                logger.warning(
                    """
                    skipping rollout line with invalid timestamp during projection \
                    thread_id=\(threadId.description, privacy: .public) \
                    rollout_path=\(rolloutPath, privacy: .public) \
                    line_start_byte_offset=\(lineStartOffset, privacy: .public) \
                    line_end_byte_offset=\(lineEndOffset, privacy: .public) \
                    expected_ordinal=\(nextOrdinal, privacy: .public) \
                    line_ordinal=\(ordinal, privacy: .public)
                    """)
                recordProjectionAnomaly(.invalidTimestamp)
                let (endOrdinalExclusive, overflow) = ordinal.addingReportingOverflow(1)
                if overflow {
                    throw ThreadStoreError.internal(
                        "rollout ordinal exceeds SQLite integer range")
                }
                projections.append(
                    .skippedOrdinalRange(
                        startOrdinal: nextOrdinal,
                        endOrdinalExclusive: endOrdinalExclusive
                    ))
                nextOrdinal = endOrdinalExclusive
                nextOffset = lineEndOffset
                lineStartOffset = lineEndOffset
                index = lineEnd
                continue
            }
        } else {
            fallbackCreatedAtMs = nil
        }

        if ordinal > nextOrdinal {
            logger.warning(
                """
                skipping missing rollout ordinal range during projection \
                thread_id=\(threadId.description, privacy: .public) \
                rollout_path=\(rolloutPath, privacy: .public) \
                line_start_byte_offset=\(lineStartOffset, privacy: .public) \
                line_end_byte_offset=\(lineEndOffset, privacy: .public) \
                expected_ordinal=\(nextOrdinal, privacy: .public) \
                line_ordinal=\(ordinal, privacy: .public) \
                skipped_ordinal_start=\(nextOrdinal, privacy: .public) \
                skipped_ordinal_end_exclusive=\(ordinal, privacy: .public)
                """)
            recordProjectionAnomaly(.forwardOrdinalGap)
            projections.append(
                .skippedOrdinalRange(
                    startOrdinal: nextOrdinal,
                    endOrdinalExclusive: ordinal
                ))
        }
        let (nextLineOrdinal, nextOverflowed) = ordinal.addingReportingOverflow(1)
        if nextOverflowed {
            throw ThreadStoreError.internal("rollout ordinal exceeds SQLite integer range")
        }
        let realtimeItem: RealtimeItem?
        if case .realtimeItem(let item) = line.item, !isInheritedSubagentHistory {
            realtimeItem = item
        } else {
            realtimeItem = nil
        }
        projections.append(
            .line(
                ProjectedRolloutLine(
                    ordinal: ordinal,
                    startByteOffset: lineStartOffset,
                    endByteOffset: lineEndOffset,
                    fallbackCreatedAtMs: fallbackCreatedAtMs,
                    changes: changes,
                    realtimeItem: realtimeItem
                )))
        nextOrdinal = nextLineOrdinal
        nextOffset = lineEndOffset
        lineStartOffset = lineEndOffset
        index = lineEnd
    }
    return (projections, nextOffset)
}

enum ProjectionAnomaly {
    case malformedJson
    case unknownLine
    case missingOrdinal
    case duplicateOrRegressedOrdinal
    case forwardOrdinalGap
    case invalidTimestamp

    func tag() -> String {
        switch self {
        case .malformedJson: return "malformed_json"
        case .unknownLine: return "unknown_line"
        case .missingOrdinal: return "missing_ordinal"
        case .duplicateOrRegressedOrdinal: return "duplicate_or_regressed_ordinal"
        case .forwardOrdinalGap: return "forward_ordinal_gap"
        case .invalidTimestamp: return "invalid_timestamp"
        }
    }
}

func recordProjectionOutcome(success: Bool) {
    _ = success
}

func recordProjectionAnomaly(_ anomaly: ProjectionAnomaly) {
    _ = anomaly
}

func isAsciiWhitespace(_ byte: UInt8) -> Bool {
    (0x09...0x0D).contains(byte) || byte == 0x20
}

func rfc3339TimestampMillis(_ timestamp: String) -> Int64? {
    guard let date = try? threadStoreDecodeDate(timestamp) else { return nil }
    return Int64(date.timeIntervalSince1970 * 1000)
}
