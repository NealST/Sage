//
//  test_support.swift
//  CodexThreadStore
//
//  Port of codex-rs/thread-store/src/local/test_support.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  `SqliteConfig::new_for_testing` maps to `SqliteConfig.newForTesting`.
//  Session files are written with `encodeRolloutLine` + FileManager (no
//  tokio). `Uuid` parameters map to `ThreadId`.
//

import CodexHistory
import CodexProtocol
import CodexRollout
import CodexState
import Foundation

public func testConfig(codexHome: String) -> LocalThreadStoreConfig {
    LocalThreadStoreConfig(
        codexHome: codexHome,
        sqlite: .newForTesting(codexHome),
        defaultModelProviderId: "test-provider"
    )
}

public func writeSessionFile(root: String, ts: String, uuid: ThreadId) throws -> String {
    try writeSessionFileWithHistoryMode(root: root, ts: ts, uuid: uuid, historyMode: .legacy)
}

public func writeSessionFileWithHistoryMode(
    root: String,
    ts: String,
    uuid: ThreadId,
    historyMode: ThreadHistoryMode
) throws -> String {
    try writeSessionFileWith(
        root: root,
        dayDir: (root as NSString)
            .appendingPathComponent("sessions/2025/01/03"),
        ts: ts,
        uuid: uuid,
        firstUserMessage: "Hello from user",
        modelProvider: "test-provider",
        historyMode: historyMode
    )
}

public func writeArchivedSessionFile(root: String, ts: String, uuid: ThreadId) throws -> String {
    try writeSessionFileWith(
        root: root,
        dayDir: (root as NSString).appendingPathComponent(ARCHIVED_SESSIONS_SUBDIR),
        ts: ts,
        uuid: uuid,
        firstUserMessage: "Archived user message",
        modelProvider: "test-provider",
        historyMode: .legacy
    )
}

public func writeSessionFileWith(
    root: String,
    dayDir: String,
    ts: String,
    uuid: ThreadId,
    firstUserMessage: String,
    modelProvider: String?,
    historyMode: ThreadHistoryMode
) throws -> String {
    try writeSessionFileWithFork(
        root: root,
        dayDir: dayDir,
        ts: ts,
        uuid: uuid,
        firstUserMessage: firstUserMessage,
        modelProvider: modelProvider,
        forkedFromId: nil,
        historyMode: historyMode
    )
}

public func writeSessionFileWithFork(
    root: String,
    dayDir: String,
    ts: String,
    uuid: ThreadId,
    firstUserMessage: String,
    modelProvider: String?,
    forkedFromId: ThreadId?,
    historyMode: ThreadHistoryMode
) throws -> String {
    try FileManager.default.createDirectory(
        atPath: dayDir,
        withIntermediateDirectories: true
    )
    let path = (dayDir as NSString).appendingPathComponent("rollout-\(ts)-\(uuid).jsonl")
    var meta = SessionMeta(
        sessionId: SessionId(uuid),
        id: uuid,
        timestamp: ts,
        cwd: root,
        originator: "test_originator",
        cliVersion: "test_version",
        source: .cli
    )
    meta.forkedFromId = forkedFromId
    meta.modelProvider = modelProvider
    meta.historyMode = historyMode
    let git = GitInfo(
        commitHash: GitSha("abcdef"),
        branch: "main",
        repositoryUrl: try? SanitizedGitUrl(parsing: "https://example.com/repo.git")
    )
    let metaLine = SessionMetaLine(meta: meta, git: git)
    let ordinal: UInt64? = historyMode == .paginated ? 0 : nil
    var text = try encodeRolloutLineString(
        RolloutLine(timestamp: ts, ordinal: ordinal, item: .sessionMeta(metaLine)))
    text += "\n"
    if historyMode == .legacy {
        let event = EventMsg.userMessage(UserMessageEvent(message: firstUserMessage))
        text += try encodeRolloutLineString(
            RolloutLine(timestamp: ts, item: .eventMsg(event)))
        text += "\n"
    }
    try text.write(toFile: path, atomically: true, encoding: .utf8)
    return path
}
