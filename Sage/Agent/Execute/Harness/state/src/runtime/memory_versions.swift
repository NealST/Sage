//
//  memory_versions.swift
//  CodexState
//
//  Port of codex-rs/state/src/runtime/memory_versions.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  v2 pool open is deferred. Path checks use FileManager against
//  `memories_v2_1.sqlite` (filename lives here so sqlite.swift is untouched).
//

import CodexProtocol
import Foundation

extension StateRuntime {
    public func memoriesForVersion(_ version: MemoryVersion) async throws -> MemoryStore {
        switch version {
        case .v1:
            return memories
        case .v2:
            throw StateRuntimeError.sqliteUnavailable("memories_v2")
        }
    }

    public func clearAllMemoryData() async throws {
        try await memories.clearMemoryData()
        if FileManager.default.fileExists(atPath: memoriesV2DbPath(sqlite)) {
            _ = try await memoriesForVersion(.v2)
            try await memories.clearMemoryData()
        }
    }

    func deleteVersionedThreadMemory(_ threadId: ThreadId) async throws {
        try await memories.deleteThreadMemory(threadId)
        if FileManager.default.fileExists(atPath: memoriesV2DbPath(sqlite)) {
            try await memoriesForVersion(.v2).deleteThreadMemory(threadId)
        }
    }
}
