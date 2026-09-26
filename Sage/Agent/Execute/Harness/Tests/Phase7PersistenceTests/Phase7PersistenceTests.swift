//
//  Phase7PersistenceTests.swift
//  Phase7PersistenceTests
//
//  Sage addition (no codex counterpart).
//  Phase 7 rollout JSONL round-trip, policy, and store tests.
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

    func testSessionIndexAppendFindRemove() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("phase7-index-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        let threadId = ThreadId()
        try appendThreadName(codexHome: home.path, threadId: threadId, name: "alpha")
        XCTAssertEqual(try findThreadNameById(codexHome: home.path, threadId: threadId), "alpha")
        try appendThreadName(codexHome: home.path, threadId: threadId, name: "beta")
        XCTAssertEqual(try findThreadNameById(codexHome: home.path, threadId: threadId), "beta")
        try removeThreadNameEntries(codexHome: home.path, threadId: threadId)
        XCTAssertNil(try findThreadNameById(codexHome: home.path, threadId: threadId))
    }

    func testMeasureAndFilterDropsOther() {
        let keep = RolloutItem.responseItem(
            ResponseItemEnvelope(item: .message(
                id: nil, role: "user", content: [.inputText(text: "hi")],
                phase: nil, internalChatMessageMetadataPassthrough: nil)))
        let drop = RolloutItem.responseItem(ResponseItemEnvelope(item: .other))
        let (persisted, measurement) = measureAndFilterRolloutItems([keep, drop], historyMode: .legacy)
        XCTAssertEqual(persisted, [keep])
        XCTAssertEqual(measurement.preFilter.items, 2)
        XCTAssertEqual(measurement.postFilter.items, 1)
        XCTAssertEqual(measurement.items.map(\.decision), [.kept, .dropped])
    }

    func testInMemoryLiveThreadCreate() async throws {
        let store = InMemoryThreadStore()
        let threadId = ThreadId()
        let live = try await LiveThread.create(
            threadStore: store,
            params: CreateThreadParams(
                sessionId: SessionId(threadId),
                threadId: threadId,
                source: .cli,
                originator: "phase7-test",
                initialWindowId: "w0",
                metadata: ThreadPersistenceMetadata(modelProvider: "openai", memoryMode: .enabled)
            )
        )
        XCTAssertEqual(live.threadId, threadId)
        let history = try await store.loadHistory(
            LoadThreadHistoryParams(threadId: threadId, includeArchived: false))
        XCTAssertFalse(history.items.isEmpty)
    }

    func testLocalArchiveUnarchiveAndDelete() async throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("phase7-archive-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        let threadId = ThreadId()
        let activePath = try writeSessionFile(
            root: home.path, ts: "2025-01-03T12-00-00", uuid: threadId)
        let store = LocalThreadStore(config: testConfig(codexHome: home.path))

        try await store.archiveThread(ArchiveThreadParams(threadId: threadId))
        XCTAssertFalse(FileManager.default.fileExists(atPath: activePath))
        let archivedPage = try await store.listThreads(
            ListThreadsParams(pageSize: 10, archived: true))
        XCTAssertEqual(archivedPage.items.map(\.threadId), [threadId])

        let restored = try await store.unarchiveThread(ArchiveThreadParams(threadId: threadId))
        XCTAssertEqual(restored.threadId, threadId)
        XCTAssertNotNil(restored.rolloutPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: restored.rolloutPath!))

        try await store.deleteThread(DeleteThreadParams(threadId: threadId))
        XCTAssertFalse(FileManager.default.fileExists(atPath: restored.rolloutPath!))
        do {
            _ = try await store.readThread(
                ReadThreadParams(threadId: threadId, includeArchived: true, includeHistory: false))
            XCTFail("deleted thread should not read")
        } catch let error as ThreadStoreError {
            switch error {
            case .invalidRequest, .threadNotFound:
                break
            default:
                XCTFail("unexpected error: \(error)")
            }
        }
    }

    func testLocalSearchAndPendingMetadata() async throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("phase7-search-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        let threadId = ThreadId()
        let store = LocalThreadStore(config: testConfig(codexHome: home.path))
        try await store.createThread(
            CreateThreadParams(
                sessionId: SessionId(threadId),
                threadId: threadId,
                source: .cli,
                originator: "phase7-search",
                initialWindowId: "w0",
                metadata: ThreadPersistenceMetadata(
                    cwd: home.path,
                    modelProvider: "openai",
                    memoryMode: .enabled
                )
            )
        )
        let user = RolloutItem.responseItem(
            ResponseItemEnvelope(item: .message(
                id: nil, role: "user", content: [.inputText(text: "searchable unique phrase")],
                phase: nil, internalChatMessageMetadataPassthrough: nil)))
        try await store.appendItems(AppendThreadItemsParams(threadId: threadId, items: [user]))
        try await store.shutdownThread(threadId: threadId)

        do {
            _ = try await store.searchThreads(
                SearchThreadsParams(pageSize: 10, archived: false, searchTerm: ""))
            XCTFail("empty search term should fail")
        } catch ThreadStoreError.invalidRequest {
            // expected
        }

        let listed = try await store.listThreads(
            ListThreadsParams(pageSize: 10, archived: false))
        XCTAssertEqual(listed.items.map(\.threadId), [threadId])
        let matches = try searchRolloutMatches(
            rgCommand: "rg-does-not-exist",
            codexHome: home.path,
            archived: false,
            searchTerm: "searchable unique phrase")
        XCTAssertFalse(matches.isEmpty)

        try await store.stagePendingThreadMetadata(
            threadId: threadId, patch: ThreadMetadataPatch(preview: "staged"))
        let staged = try await store.readPendingThreadMetadata(threadId: threadId)
        XCTAssertEqual(staged?.preview, "staged")
        try await store.removePendingThreadMetadata(threadId: threadId)
        let cleared = try await store.readPendingThreadMetadata(threadId: threadId)
        XCTAssertNil(cleared)
    }

    func testStateRuntimeBackfillThrowsUntilSqlite() async throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("phase7-state-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        let runtime = try StateRuntime.initialize(
            sqlite: SqliteConfig(sqliteHome: home.path),
            defaultProvider: "openai"
        )
        do {
            _ = try await runtime.getBackfillState()
            XCTFail("backfill should throw until GRDB")
        } catch StateRuntimeError.sqliteUnavailable(let area) {
            XCTAssertEqual(area, "backfill")
        }

        let dbPath = (home.path as NSString).appendingPathComponent("state_5.sqlite")
        try Data().write(to: URL(fileURLWithPath: dbPath))
        let backups = try await backupRuntimeDbForFreshStart(dbPath: dbPath)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dbPath))
        XCTAssertFalse(backups.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: backups[0].backupPath))
    }

    func testLocalUpdateMetadataNameAndEmptyPatch() async throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("phase7-meta-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        let threadId = ThreadId()
        _ = try writeSessionFile(root: home.path, ts: "2025-01-03T12-00-00", uuid: threadId)
        let store = LocalThreadStore(config: testConfig(codexHome: home.path))

        let empty = try await store.updateThreadMetadata(
            UpdateThreadMetadataParams(
                threadId: threadId,
                patch: ThreadMetadataPatch(),
                includeArchived: false
            )
        )
        XCTAssertEqual(empty?.threadId, threadId)

        let renamed = try await store.updateThreadMetadata(
            UpdateThreadMetadataParams(
                threadId: threadId,
                patch: ThreadMetadataPatch(name: "alpha"),
                includeArchived: false
            )
        )
        XCTAssertEqual(renamed?.threadId, threadId)
        XCTAssertEqual(try findThreadNameById(codexHome: home.path, threadId: threadId), "alpha")
    }

    func testPaginatedHistoryThrowsUntilSqlite() async throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("phase7-history-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        let threadId = ThreadId()
        _ = try writeSessionFile(root: home.path, ts: "2025-01-03T12-00-00", uuid: threadId)
        let store = LocalThreadStore(config: testConfig(codexHome: home.path))
        XCTAssertFalse(store.supportsPaginatedHistoryLists())

        do {
            _ = try await store.searchThreadOccurrences(
                SearchThreadOccurrencesParams(threadId: threadId, searchTerm: "", pageSize: 10))
            XCTFail("empty search term should fail")
        } catch ThreadStoreError.invalidRequest {
            // expected
        }

        do {
            _ = try await store.listTurns(
                ListTurnsParams(
                    threadId: threadId,
                    includeArchived: false,
                    pageSize: 10,
                    sortDirection: .desc
                )
            )
            XCTFail("listTurns should throw until GRDB")
        } catch ThreadStoreError.unsupported(let operation) {
            XCTAssertEqual(operation, "paginated_threads")
        }
    }

    func testGoalAndMemoryStoresThrowUntilSqlite() async throws {
        let memories = MemoryStore()
        let unused = try await memories.recordStage1OutputUsage([])
        XCTAssertEqual(unused, 0)
        do {
            _ = try await memories.recordStage1OutputUsage([ThreadId()])
            XCTFail("memories should throw until GRDB")
        } catch StateRuntimeError.sqliteUnavailable(let area) {
            XCTAssertEqual(area, "memories")
        }

        do {
            _ = try await GoalStore().getThreadGoal(ThreadId())
            XCTFail("goals should throw until GRDB")
        } catch StateRuntimeError.sqliteUnavailable(let area) {
            XCTAssertEqual(area, "goals")
        }
    }

    func testLegacyLineParserSkipsRetiredAndBlank() throws {
        XCTAssertNil(try unwrapLegacy(parseLegacyRolloutLine(Data("   \n".utf8))))
        let retired = Data("""
        {"timestamp":"2025-01-03T12:00:00Z","type":"event_msg","payload":{"type":"thread_name_updated","thread_name":"x"}}
        """.utf8)
        XCTAssertNil(try unwrapLegacy(parseLegacyRolloutLine(retired)))

        let sandbox = Data("""
        {"timestamp":"2025-01-03T12:00:00Z","type":"turn_context","payload":{"sandbox_policy":{"mode":"read-only"}}}
        """.utf8)
        switch parseLegacyRolloutLine(sandbox) {
        case .success(let line):
            XCTAssertNotNil(line)
        case .failure:
            break
        }
    }

    func testMigrateRolloutsDryRunAndApply() async throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("phase7-migrate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        let legacyId = ThreadId()
        let paginatedId = ThreadId()
        _ = try writeSessionFile(root: home.path, ts: "2025-01-03T12-00-00", uuid: legacyId)
        _ = try writeSessionFileWithHistoryMode(
            root: home.path, ts: "2025-01-03T12-00-01", uuid: paginatedId, historyMode: .paginated)

        let store = LocalThreadStore(config: testConfig(codexHome: home.path))
        try await store.migrateRolloutsOnStartup()

        let report = try await store.migrateRollouts(RolloutMigrationOptions())
        let statuses = Dictionary(
            uniqueKeysWithValues: report.outcomes.compactMap { outcome in
                outcome.threadId.map { ($0, outcome.status) }
            })
        XCTAssertEqual(statuses[legacyId], .eligible)
        XCTAssertEqual(statuses[paginatedId], .alreadyPaginated)

        do {
            _ = try await store.migrateRollouts(RolloutMigrationOptions(mode: .apply))
            XCTFail("apply should throw until GRDB")
        } catch ThreadStoreError.unsupported(let operation) {
            XCTAssertEqual(operation, "rollout_migration")
        }

        let threadId = ThreadId()
        XCTAssertTrue(migrationJournalPath(codexHome: home.path, threadId: threadId)
            .hasSuffix("\(threadId).pending"))
        XCTAssertEqual(try pendingMigrationThreadIds(codexHome: home.path), [])
        let staged = try stagedRolloutPath("/tmp/rollout-x.jsonl")
        XCTAssertTrue(staged.hasSuffix(".rollout-x.jsonl.paginated.tmp"))
    }

    func testRollbackDropsLastUserTurns() {
        let user = ResponseItemEnvelope(item: .message(
            id: nil, role: "user", content: [.inputText(text: "hi")],
            phase: nil, internalChatMessageMetadataPassthrough: nil))
        let assistant = ResponseItemEnvelope(item: .message(
            id: nil, role: "assistant", content: [.inputText(text: "ok")],
            phase: nil, internalChatMessageMetadataPassthrough: nil))
        var history = [user, assistant, user, assistant]
        dropLastNUserTurns(&history, numTurns: 1)
        XCTAssertEqual(history.count, 2)
        XCTAssertTrue(countsAsBoundary(user.item))
        XCTAssertFalse(countsAsBoundary(assistant.item))
    }

    func testCanonicalizerWritesPaginatedHead() throws {
        let threadId = ThreadId()
        var meta = SessionMeta(
            id: threadId,
            timestamp: "2025-01-03T12:00:00Z",
            cwd: "/tmp",
            originator: "sage",
            source: .cli
        )
        meta.historyMode = .legacy
        let line = RolloutLine(
            timestamp: "2025-01-03T12:00:00Z",
            item: .sessionMeta(SessionMetaLine(meta: meta))
        )
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("phase7-canon-\(UUID().uuidString).jsonl")
        FileManager.default.createFile(atPath: url.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: url) }
        let handle = try FileHandle(forUpdating: url)
        defer { try? handle.close() }
        var canonicalizer = LegacyRolloutCanonicalizer(threadId: threadId)
        _ = try canonicalizer.writeHeadSessionMeta(line, to: handle)
        try handle.synchronize()
        let text = try String(contentsOf: url, encoding: .utf8)
        let decoded = try parseRolloutLine(text.trimmingCharacters(in: .newlines))
        guard case .sessionMeta(let written) = decoded.item else {
            return XCTFail("expected session_meta")
        }
        XCTAssertEqual(written.meta.historyMode, .paginated)
        XCTAssertEqual(decoded.ordinal, 0)
    }
}

private func unwrapLegacy(_ result: Result<RolloutLine?, LegacyRolloutParseError>) throws -> RolloutLine? {
    switch result {
    case .success(let line): return line
    case .failure(let error): throw error
    }
}
