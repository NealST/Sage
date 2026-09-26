//
//  recorder.swift
//  CodexRollout
//
//  Port of codex-rs/rollout/src/recorder.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Background mpsc writer maps to an actor-isolated `JsonlWriter`. Git
//  enrichment, compression materialize, and state-db listing are deferred.
//  JSONL line format is the canonical flattened `{timestamp,ordinal?,type,payload}`.
//

import CodexHistory
import CodexProtocol
import CodexUtils
import Foundation
import os

public enum RolloutRecorderParams: Sendable {
    case create(
        sessionId: SessionId,
        conversationId: ThreadId,
        rolloutIdOverride: RolloutId?,
        forkedFromId: ThreadId?,
        forkedFromOrdinalExclusive: UInt64?,
        parentThreadId: ThreadId?,
        source: SessionSource,
        threadSource: ThreadSource?,
        originator: String,
        creatorUserId: String?,
        creatorAccountId: String?,
        baseInstructions: BaseInstructions?,
        historyMode: ThreadHistoryMode,
        historyBase: HistoryPosition?,
        subagentHistoryStartOrdinal: UInt64?
    )
    case resume(path: String)

    public static func new(
        conversationId: ThreadId,
        forkedFromId: ThreadId? = nil,
        parentThreadId: ThreadId? = nil,
        source: SessionSource,
        threadSource: ThreadSource? = nil,
        originator: String,
        baseInstructions: BaseInstructions? = nil
    ) -> RolloutRecorderParams {
        .create(
            sessionId: SessionId(conversationId),
            conversationId: conversationId,
            rolloutIdOverride: nil,
            forkedFromId: forkedFromId,
            forkedFromOrdinalExclusive: nil,
            parentThreadId: parentThreadId,
            source: source,
            threadSource: threadSource,
            originator: originator,
            creatorUserId: nil,
            creatorAccountId: nil,
            baseInstructions: baseInstructions,
            historyMode: .legacy,
            historyBase: nil,
            subagentHistoryStartOrdinal: nil
        )
    }
}

/// Writes canonical session rollout items to JSONL.
public final class RolloutRecorder: @unchecked Sendable {
    public let rolloutPath: String
    private let lock = OSAllocatedUnfairLock<WriterState?>(initialState: nil)

    public init(rolloutPath: String, state: WriterState) {
        self.rolloutPath = rolloutPath
        lock.withLock { $0 = state }
    }

    public static func create(
        config: RolloutConfig,
        params: RolloutRecorderParams
    ) throws -> RolloutRecorder {
        switch params {
        case .create(
            let sessionId, let conversationId, let rolloutIdOverride, let forkedFromId,
            let forkedFromOrdinalExclusive, let parentThreadId, let source, let threadSource,
            let originator, let creatorUserId, let creatorAccountId, let baseInstructions,
            let historyMode, let historyBase, let subagentHistoryStartOrdinal
        ):
            let (path, timestamp) = try precomputeNewRolloutPath(
                config: config,
                threadId: conversationId,
                rolloutIdOverride: rolloutIdOverride
            )
            var meta = SessionMeta(
                sessionId: sessionId,
                id: conversationId,
                timestamp: rfc3339(timestamp),
                cwd: config.cwd,
                originator: originator,
                source: source
            )
            meta.forkedFromId = forkedFromId
            meta.forkedFromOrdinalExclusive = forkedFromOrdinalExclusive
            meta.parentThreadId = parentThreadId
            meta.threadSource = threadSource
            meta.creatorUserId = creatorUserId
            meta.creatorAccountId = creatorAccountId
            meta.baseInstructions = baseInstructions
            meta.historyMode = historyMode
            meta.historyBase = historyBase
            meta.subagentHistoryStartOrdinal = subagentHistoryStartOrdinal
            var ordinal = RolloutOrdinalState.forNewRollout(
                historyMode: historyMode, historyBase: historyBase)
            try FileManager.default.createDirectory(
                at: URL(fileURLWithPath: path).deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            FileManager.default.createFile(atPath: path, contents: nil)
            let recorder = RolloutRecorder(
                rolloutPath: path,
                state: WriterState(ordinal: ordinal, historyMode: historyMode)
            )
            try recorder.recordItems([.sessionMeta(SessionMetaLine(meta: meta))])
            try recorder.flush()
            return recorder
        case .resume(let path):
            let ordinal = try ordinalStateForRollout(at: URL(fileURLWithPath: path))
            return RolloutRecorder(
                rolloutPath: path,
                state: WriterState(ordinal: ordinal, historyMode: .legacy)
            )
        }
    }

    public func recordItems(_ items: [RolloutItem]) throws {
        try lock.withLock { state in
            guard var current = state else { return }
            let persisted = persistedRolloutItems(items, historyMode: current.historyMode)
            guard !persisted.isEmpty else { return }
            current.pending.append(contentsOf: persisted)
            state = current
        }
    }

    public func flush() throws {
        try lock.withLock { state in
            guard var current = state else { return }
            let handle = try FileHandle(forUpdating: URL(fileURLWithPath: rolloutPath))
            defer { try? handle.close() }
            try handle.seekToEnd()
            for item in current.pending {
                let ordinal = try current.ordinal.current()
                let line = RolloutLine(
                    timestamp: rfc3339(Date()),
                    ordinal: ordinal,
                    item: item
                )
                var data = Data(try encodeRolloutLineString(line).utf8)
                data.append(UInt8(ascii: "\n"))
                try handle.write(contentsOf: data)
                current.ordinal.advance()
            }
            current.pending.removeAll()
            try handle.synchronize()
            state = current
        }
    }

    public func persist() throws { try flush() }

    public func shutdown() throws { try flush() }

    public func readLines() throws -> [RolloutLine] {
        let text = try String(contentsOfFile: rolloutPath, encoding: .utf8)
        return try text.split(separator: "\n", omittingEmptySubsequences: true).map {
            try parseRolloutLine(String($0))
        }
    }

    /// Loads every non-blank JSONL record, counting parse failures without aborting.
    public static func loadRolloutItems(
        path: String
    ) throws -> (items: [RolloutItem], threadId: ThreadId?, parseErrors: Int) {
        var items: [RolloutItem] = []
        var threadId: ThreadId?
        var parseErrors = 0
        var sawNonEmptyLine = false
        let text = try String(contentsOfFile: path, encoding: .utf8)
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
            sawNonEmptyLine = true
            let data = Data(line.utf8)
            let value: JSONValue
            do {
                value = try JSONDecoder().decode(JSONValue.self, from: data)
            } catch {
                parseErrors = parseErrors &+ 1
                continue
            }
            if stripLegacyGhostSnapshotRolloutLine(value) { continue }
            if threadId == nil {
                try rejectUnknownThreadHistoryMode(value)
            }
            let rolloutLine: RolloutLine
            do {
                rolloutLine = try decodeRolloutLine(value)
            } catch {
                parseErrors = parseErrors &+ 1
                continue
            }
            if threadId == nil, case .sessionMeta(let sessionMetaLine) = rolloutLine.item {
                threadId = sessionMetaLine.meta.id
            }
            items.append(rolloutLine.item)
        }
        if !sawNonEmptyLine {
            throw IOError.other("empty session file")
        }
        return (items, threadId, parseErrors)
    }
}

func rejectUnknownThreadHistoryMode(_ value: JSONValue) throws {
    guard let object = value.objectValue,
          object["type"]?.stringValue == "session_meta"
    else { return }
    guard let historyMode = object["payload"]?.objectValue?["history_mode"] else { return }
    let data = try JSONEncoder().encode(historyMode)
    do {
        _ = try JSONDecoder().decode(ThreadHistoryMode.self, from: data)
    } catch {
        throw IOError.other("invalid session metadata history_mode: \(error)")
    }
}

private func stripLegacyGhostSnapshotRolloutLine(_ value: JSONValue) -> Bool {
    guard let object = value.objectValue,
          object["type"]?.stringValue == "response_item",
          object["payload"]?.objectValue?["type"]?.stringValue == "ghost_snapshot"
    else { return false }
    return true
}

public struct WriterState: Sendable {
    var pending: [RolloutItem] = []
    var ordinal: RolloutOrdinalState
    var historyMode: ThreadHistoryMode

    init(ordinal: RolloutOrdinalState, historyMode: ThreadHistoryMode) {
        self.ordinal = ordinal
        self.historyMode = historyMode
    }
}

public func appendRolloutItemToPath(_ item: RolloutItem, path: String) throws {
    let recorder = try RolloutRecorder.create(
        config: RolloutConfig(codexHome: NSTemporaryDirectory()),
        params: .resume(path: path)
    )
    try recorder.recordItems([item])
    try recorder.flush()
}

func precomputeNewRolloutPath(
    config: RolloutConfig,
    threadId: ThreadId,
    rolloutIdOverride: RolloutId?
) throws -> (String, Date) {
    let timestamp = Date()
    let calendar = Calendar.current
    let parts = calendar.dateComponents([.year, .month, .day], from: timestamp)
    let year = String(parts.year ?? 0)
    let month = String(format: "%02d", parts.month ?? 0)
    let day = String(format: "%02d", parts.day ?? 0)
    let dir = ((((config.codexHome as NSString)
        .appendingPathComponent(SESSIONS_SUBDIR) as NSString)
        .appendingPathComponent(year) as NSString)
        .appendingPathComponent(month) as NSString)
        .appendingPathComponent(day)
    let filename = RolloutFileName(
        timestamp: timestamp,
        threadId: threadId,
        rolloutId: rolloutIdOverride ?? threadId
    ).render()
    return ((dir as NSString).appendingPathComponent(filename), timestamp)
}

private func rfc3339(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
}
