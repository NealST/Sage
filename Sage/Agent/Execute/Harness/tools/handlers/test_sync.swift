//
//  test_sync.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/handlers/test_sync.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Git-enrichment wait waits for Phase 5 turn metadata. Barriers use a
//  process-local actor instead of tokio Mutex.
//

import CodexCore
import CodexProtocol
import Foundation

let TEST_SYNC_DEFAULT_TIMEOUT_MS: UInt64 = 1_000

struct BarrierArgs: Decodable {
    var id: String
    var participants: Int
    var timeoutMs: UInt64

    enum CodingKeys: String, CodingKey {
        case id, participants
        case timeoutMs = "timeout_ms"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        participants = try container.decode(Int.self, forKey: .participants)
        timeoutMs = try container.decodeIfPresent(UInt64.self, forKey: .timeoutMs)
            ?? TEST_SYNC_DEFAULT_TIMEOUT_MS
    }
}

struct TestSyncArgs: Decodable {
    var sleepBeforeMs: UInt64?
    var sleepAfterMs: UInt64?
    var barrier: BarrierArgs?
    var waitForGitEnrichment: Bool

    enum CodingKeys: String, CodingKey {
        case sleepBeforeMs = "sleep_before_ms"
        case sleepAfterMs = "sleep_after_ms"
        case barrier
        case waitForGitEnrichment = "wait_for_git_enrichment"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sleepBeforeMs = try container.decodeIfPresent(UInt64.self, forKey: .sleepBeforeMs)
        sleepAfterMs = try container.decodeIfPresent(UInt64.self, forKey: .sleepAfterMs)
        barrier = try container.decodeIfPresent(BarrierArgs.self, forKey: .barrier)
        waitForGitEnrichment = try container.decodeIfPresent(Bool.self, forKey: .waitForGitEnrichment) ?? false
    }
}

actor TestSyncBarrierStore {
    static let shared = TestSyncBarrierStore()

    private var barriers: [String: BarrierState] = [:]

    struct BarrierState {
        var continuations: [CheckedContinuation<Void, Error>] = []
        var participants: Int
    }

    func wait(_ args: BarrierArgs) async throws {
        if args.participants == 0 {
            throw FunctionCallError.respondToModel("barrier participants must be greater than zero")
        }
        if args.timeoutMs == 0 {
            throw FunctionCallError.respondToModel("barrier timeout must be greater than zero")
        }
        if var existing = barriers[args.id] {
            if existing.participants != args.participants {
                throw FunctionCallError.respondToModel(
                    "barrier \(args.id) already registered with \(existing.participants) participants"
                )
            }
            if existing.continuations.count + 1 >= args.participants {
                let waiting = existing.continuations
                barriers.removeValue(forKey: args.id)
                waiting.forEach { $0.resume() }
                return
            }
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                existing.continuations.append(continuation)
                barriers[args.id] = existing
            }
            return
        }
        if args.participants == 1 { return }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            barriers[args.id] = BarrierState(continuations: [continuation], participants: args.participants)
        }
    }
}

struct TestSyncHandler: CoreToolRuntime {
    func toolName() -> ToolName { ToolName(plain: "test_sync_tool") }
    func spec() -> ToolSpec { createTestSyncTool() }
    func supportsParallelToolCalls() -> Bool { true }

    func handle(_ invocation: ToolInvocation) async throws -> any ToolOutput {
        guard case .function(let arguments) = invocation.payload else {
            throw FunctionCallError.respondToModel(
                "test_sync_tool handler received unsupported payload"
            )
        }
        let args: TestSyncArgs = try parseArguments(arguments)
        if let delay = args.sleepBeforeMs, delay > 0 {
            try await Task.sleep(for: .milliseconds(Int64(delay)))
        }
        if let barrier = args.barrier {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask { try await TestSyncBarrierStore.shared.wait(barrier) }
                group.addTask {
                    try await Task.sleep(for: .milliseconds(Int64(barrier.timeoutMs)))
                    throw FunctionCallError.respondToModel("test_sync_tool barrier wait timed out")
                }
                try await group.next()
                group.cancelAll()
            }
        }
        if args.waitForGitEnrichment {
            throw FunctionCallError.respondToModel(
                "test_sync_tool git enrichment wait is not wired (Phase 5)"
            )
        }
        if let delay = args.sleepAfterMs, delay > 0 {
            try await Task.sleep(for: .milliseconds(Int64(delay)))
        }
        return boxedToolOutput(FunctionToolOutput.fromText("ok", success: true))
    }
}
