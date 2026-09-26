//
//  create_thread.swift
//  CodexThreadStore
//
//  Port of codex-rs/thread-store/src/local/create_thread.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  `RolloutRecorderParams` builder chain maps to the Swift enum case.
//  Writer-lock injection is handled by the caller (`LocalThreadStore`).
//

import CodexProtocol
import CodexRollout
import Foundation

func createLocalThreadRecorder(
    store: LocalThreadStore,
    params: CreateThreadParams
) throws -> RolloutRecorder {
    guard let cwd = params.metadata.cwd, !cwd.isEmpty else {
        throw ThreadStoreError.invalidRequest("local thread store requires a cwd")
    }
    let config = RolloutConfig(
        codexHome: store.config.codexHome,
        sqlite: store.config.sqlite,
        cwd: cwd,
        modelProviderId: params.metadata.modelProvider,
        generateMemories: params.metadata.memoryMode == .enabled
    )
    let forkedFromOrdinalExclusive: UInt64?
    if params.forkedFromId != nil, let historyBase = params.historyBase {
        forkedFromOrdinalExclusive = historyBase.endOrdinalExclusive
    } else {
        forkedFromOrdinalExclusive = nil
    }
    do {
        return try RolloutRecorder.create(
            config: config,
            params: .create(
                sessionId: params.sessionId,
                conversationId: params.threadId,
                rolloutIdOverride: nil,
                forkedFromId: params.forkedFromId,
                forkedFromOrdinalExclusive: forkedFromOrdinalExclusive,
                parentThreadId: params.parentThreadId,
                source: params.source,
                threadSource: params.threadSource,
                originator: params.originator,
                creatorUserId: params.creatorUserId,
                creatorAccountId: params.creatorAccountId,
                baseInstructions: params.baseInstructions,
                historyMode: params.historyMode,
                historyBase: params.historyBase,
                subagentHistoryStartOrdinal: params.subagentHistoryStartOrdinal
            )
        )
    } catch {
        throw ThreadStoreError.internal(
            "failed to initialize local thread recorder: \(error)")
    }
}
