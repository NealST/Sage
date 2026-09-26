//
//  mod.swift
//  Sage
//
//  Port of codex-rs/core/src/unified_exec/mod.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Session / TurnContext / plugin sidecar fields are omitted until Phase 5.
//  Process-store, yield clamps, and local PTY spawn are implemented.
//

import CodexAsyncUtils
import CodexProtocol
import CodexSandboxing
import CodexShellCommand
import CodexUtils
import Foundation

let MIN_YIELD_TIME_MS: UInt64 = 250
let WINDOWS_INITIAL_EXEC_YIELD_TIME_FLOOR_MS: UInt64 = 10_000
let MIN_EMPTY_YIELD_TIME_MS: UInt64 = 5_000
let MAX_YIELD_TIME_MS: UInt64 = 30_000
let DEFAULT_MAX_BACKGROUND_TERMINAL_TIMEOUT_MS: UInt64 = 300_000
let DEFAULT_MAX_OUTPUT_TOKENS = 10_000
let UNIFIED_EXEC_OUTPUT_MAX_BYTES = 1024 * 1024
let UNIFIED_EXEC_OUTPUT_MAX_TOKENS = UNIFIED_EXEC_OUTPUT_MAX_BYTES / 4
let MAX_UNIFIED_EXEC_PROCESSES = 64
private let MAX_TRACE_ID_BYTES = 256

public enum UnifiedExecShellMode: Equatable, Sendable {
    case direct
    case login
    case zshFork
}

struct UnifiedExecContext {
    var cancellationToken: CancellationToken
    var callId: String
}

struct ExecCommandRequest {
    var command: [String]
    var shellType: ShellType
    var hookCommand: String
    var processId: Int32
    var yieldTimeMs: UInt64
    var maxOutputTokens: Int?
    var cwd: PathUri
    var sandboxCwd: PathUri
    var shellMode: UnifiedExecShellMode
    var network: NetworkProxy?
    var tty: Bool
    var sandboxPermissions: SandboxPermissions
    var additionalPermissions: AdditionalPermissionProfile?
    var additionalPermissionsPreapproved: Bool
    var justification: String?
    var prefixRule: [String]?
}

struct WriteStdinRequest {
    var processId: Int32
    var input: String
    var yieldTimeMs: UInt64
    var maxOutputTokens: Int?
}

final class ProcessStore {
    var processes: [Int32: ProcessEntry] = [:]
    var reservedProcessIds: Set<Int32> = []

    func remove(_ processId: Int32) -> ProcessEntry? {
        if !shouldUseDeterministicProcessIds() {
            reservedProcessIds.remove(processId)
        }
        return processes.removeValue(forKey: processId)
    }
}

final class UnifiedExecProcessManager: @unchecked Sendable {
    let processStore = NSLock()
    var store = ProcessStore()
    var maxWriteStdinYieldTimeMs: UInt64

    init(maxWriteStdinYieldTimeMs: UInt64 = DEFAULT_MAX_BACKGROUND_TERMINAL_TIMEOUT_MS) {
        self.maxWriteStdinYieldTimeMs = max(maxWriteStdinYieldTimeMs, MIN_EMPTY_YIELD_TIME_MS)
    }
}

final class ProcessEntry {
    var process: UnifiedExecProcess
    var callId: String
    var processId: Int32
    var cwd: PathUri
    var hookCommand: String
    var tty: Bool
    var environmentId: String
    var permissions: TerminalPermissions
    var lastUsed: ContinuousClock.Instant

    init(
        process: UnifiedExecProcess,
        callId: String,
        processId: Int32,
        cwd: PathUri,
        hookCommand: String,
        tty: Bool,
        environmentId: String,
        permissions: TerminalPermissions
    ) {
        self.process = process
        self.callId = callId
        self.processId = processId
        self.cwd = cwd
        self.hookCommand = hookCommand
        self.tty = tty
        self.environmentId = environmentId
        self.permissions = permissions
        self.lastUsed = .now
    }
}

func clampYieldTime(_ yieldTimeMs: UInt64) -> UInt64 {
    min(max(yieldTimeMs, MIN_YIELD_TIME_MS), MAX_YIELD_TIME_MS)
}

func resolveMaxTokens(_ maxTokens: Int?) -> Int {
    maxTokens ?? DEFAULT_MAX_OUTPUT_TOKENS
}

func formatOutputOmissionMarker(_ omittedBytes: Int) -> String {
    "... \(omittedBytes) bytes omitted ..."
}

func generateChunkId() -> String {
    String((0..<6).map { _ in String(format: "%x", Int.random(in: 0..<16)) }.joined())
}

func traceId(_ id: String) -> String? {
    (!id.isEmpty && id.utf8.count <= MAX_TRACE_ID_BYTES) ? id : nil
}
