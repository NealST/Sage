//
//  test_support.swift
//  CodexState
//
//  Port of codex-rs/state/src/runtime/test_support.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Available in the library (upstream is `cfg(test)` only). `PathBuf` maps
//  to `String`; timestamps use Foundation `Date`.
//

import CodexProtocol
import Foundation

func uniqueTempDir() -> String {
    let nanos = UInt64((Date().timeIntervalSince1970 * 1_000_000_000).rounded(.towardZero))
    return (FileManager.default.temporaryDirectory.path as NSString)
        .appendingPathComponent("codex-state-runtime-test-\(nanos)-\(UUID().uuidString)")
}

func testThreadMetadata(
    codexHome: String,
    threadId: ThreadId,
    cwd: String
) -> ThreadMetadata {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    return ThreadMetadata(
        originator: nil,
        creatorUserId: nil,
        creatorAccountId: nil,
        id: threadId,
        rolloutPath: (codexHome as NSString).appendingPathComponent("rollout-\(threadId).jsonl"),
        createdAt: now,
        updatedAt: now,
        recencyAt: now,
        source: "cli",
        historyMode: .legacy,
        threadSource: nil,
        agentNickname: nil,
        agentRole: nil,
        agentPath: nil,
        modelProvider: "test-provider",
        model: "gpt-5",
        reasoningEffort: .medium,
        cwd: cwd,
        cliVersion: "0.0.0",
        title: "",
        name: nil,
        preview: "hello",
        sandboxPolicy: enumToString(SandboxPolicy.newReadOnlyPolicy()),
        approvalMode: enumToString(AskForApproval.onRequest),
        tokensUsed: 0,
        firstUserMessage: "hello",
        archivedAt: nil,
        section: nil,
        sectionPosition: nil,
        sectionEnteredAt: nil,
        projectId: nil,
        daybreakEnabled: nil,
        gitSha: nil,
        gitBranch: nil,
        gitOriginUrl: nil
    )
}
