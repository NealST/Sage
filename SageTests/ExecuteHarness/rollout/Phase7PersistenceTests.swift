//
//  Phase7PersistenceTests.swift
//  SageTests
//
//  Sage addition (no codex counterpart).
//  Phase 7 rollout JSONL round-trip, policy, and truncation tests.
//

import CodexHistory
import CodexProtocol
import CodexRollout
import CodexState
import CodexThreadStore
import Foundation
import XCTest

final class Phase7PersistenceTests: XCTestCase {
    func testRolloutLineRoundTripSessionMeta() throws {
        var meta = SessionMeta(
            id: ThreadId(),
            timestamp: "2026-01-02T03:04:05Z",
            cwd: "/tmp",
            originator: "sage",
            source: .cli
        )
        meta.historyMode = .paginated
        let line = RolloutLine(
            timestamp: "2026-01-02T03:04:05.000Z",
            ordinal: 0,
            item: .sessionMeta(SessionMetaLine(meta: meta))
        )
        let encoded = try encodeRolloutLineString(line)
        let decoded = try parseRolloutLine(encoded)
        XCTAssertEqual(decoded.timestamp, line.timestamp)
        XCTAssertEqual(decoded.ordinal, 0)
        guard case .sessionMeta(let decodedMeta) = decoded.item else {
            return XCTFail("expected session_meta")
        }
        XCTAssertEqual(decodedMeta.meta.id, meta.id)
        XCTAssertEqual(decodedMeta.meta.historyMode, .paginated)
        XCTAssertEqual(decodedMeta.meta.source, SessionSource.cli)
    }

    func testPersistedRolloutItemsDropsOtherResponse() {
        let keep = RolloutItem.responseItem(
            ResponseItemEnvelope(item: .message(
                id: nil, role: "user", content: [.inputText(text: "hello")],
                phase: nil, internalChatMessageMetadataPassthrough: nil)))
        let drop = RolloutItem.responseItem(
            ResponseItemEnvelope(item: .other))
        let persisted = persistedRolloutItems([keep, drop], historyMode: .legacy)
        XCTAssertEqual(persisted.count, 1)
        XCTAssertEqual(persisted[0], keep)
    }

    func testRecorderWriteAndReplay() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("phase7-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        let threadId = ThreadId()
        let recorder = try RolloutRecorder.create(
            config: RolloutConfig(codexHome: home.path, cwd: "/tmp"),
            params: .new(
                conversationId: threadId,
                source: .cli,
                originator: "sage-test"
            )
        )
        let user = RolloutItem.responseItem(
            ResponseItemEnvelope(item: .message(
                id: nil, role: "user", content: [.inputText(text: "ping")],
                phase: nil, internalChatMessageMetadataPassthrough: nil)))
        try recorder.recordItems([user])
        try recorder.flush()

        let lines = try recorder.readLines()
        XCTAssertGreaterThanOrEqual(lines.count, 2)
        guard case .sessionMeta(let meta) = lines[0].item else {
            return XCTFail("first line must be session_meta")
        }
        XCTAssertEqual(meta.meta.id, threadId)
        guard case .responseItem(let envelope) = lines[1].item else {
            return XCTFail("second line must be response_item")
        }
        XCTAssertTrue(envelope.item.isUserMessage())
        XCTAssertTrue(recorder.rolloutPath.contains("rollout-"))
        XCTAssertTrue(recorder.rolloutPath.hasSuffix(".jsonl"))
    }

    func testRolloutFileNameParseRender() throws {
        let threadId = try ThreadId.fromString("5973b6c0-94b8-487b-a530-2aeb6098ae0e")
        let name = "rollout-2025-05-07T17-24-21-\(threadId).jsonl"
        let parsed = RolloutFileName.parse(name)
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.threadId, threadId)
        XCTAssertEqual(parsed?.rolloutId, threadId)
        XCTAssertEqual(parsed?.render(), name)
    }

    func testSqliteConfigPaths() {
        let config = SqliteConfig(sqliteHome: "/tmp/codex-home")
        XCTAssertTrue(config.stateDbPath().hasSuffix("state_5.sqlite"))
        XCTAssertTrue(config.logsDbPath().hasSuffix("logs_2.sqlite"))
    }

    func testThreadStoreErrorCases() {
        let error = ThreadStoreError.threadNotFound("abc")
        XCTAssertEqual(error, .threadNotFound("abc"))
    }
}
