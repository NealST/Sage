//
//  process_manager.swift
//  Sage
//
//  Port of codex-rs/core/src/unified_exec/process_manager.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: partial
//
//  Process-id allocation, env overlay, and local spawn are implemented.
//  Session/orchestrator/approval/plugin paths wait on Phase 4–5.
//

import CodexAsyncUtils
import CodexProtocol
import CodexSandboxing
import CodexUtils
import Foundation

let UNIFIED_EXEC_ENV: [(String, String)] = [
    ("NO_COLOR", "1"),
    ("TERM", "dumb"),
    ("LANG", "C.UTF-8"),
    ("LC_CTYPE", "C.UTF-8"),
    ("LC_ALL", "C.UTF-8"),
    ("COLORTERM", ""),
    ("PAGER", "cat"),
    ("GIT_PAGER", "cat"),
    ("GH_PAGER", "cat"),
    ("CODEX_CI", "1"),
]

private let forceDeterministicProcessIds = LockedFlag()

private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func store(_ enabled: Bool) { lock.lock(); value = enabled; lock.unlock() }
    func load() -> Bool { lock.lock(); defer { lock.unlock() }; return value }
}

func setDeterministicProcessIdsForTests(_ enabled: Bool) {
    forceDeterministicProcessIds.store(enabled)
}

func shouldUseDeterministicProcessIds() -> Bool {
    forceDeterministicProcessIds.load()
}

func applyUnifiedExecEnv(_ env: [String: String]) -> [String: String] {
    var env = env
    for (key, value) in UNIFIED_EXEC_ENV {
        env[key] = value
    }
    return env
}

extension UnifiedExecProcessManager {
    func allocateProcessId() -> Int32 {
        processStore.lock()
        defer { processStore.unlock() }
        if shouldUseDeterministicProcessIds() {
            let next = (store.reservedProcessIds.max() ?? 0) + 1
            store.reservedProcessIds.insert(next)
            return next
        }
        while true {
            let candidate = Int32.random(in: 1...Int32.max)
            if store.processes[candidate] == nil && !store.reservedProcessIds.contains(candidate) {
                store.reservedProcessIds.insert(candidate)
                return candidate
            }
        }
    }

    func releaseProcessId(_ processId: Int32) {
        processStore.lock()
        store.reservedProcessIds.remove(processId)
        store.processes.removeValue(forKey: processId)
        processStore.unlock()
    }

    func process(for processId: Int32) -> ProcessEntry? {
        processStore.lock(); defer { processStore.unlock() }
        return store.processes[processId]
    }

    func insert(_ entry: ProcessEntry) {
        processStore.lock()
        store.processes[entry.processId] = entry
        processStore.unlock()
    }

    func evictIfNeeded() {
        processStore.lock()
        while store.processes.count >= MAX_UNIFIED_EXEC_PROCESSES {
            let oldest = store.processes.values.min { $0.lastUsed < $1.lastUsed }
            if let oldest {
                store.processes.removeValue(forKey: oldest.processId)
                oldest.process.terminate()
            } else {
                break
            }
        }
        processStore.unlock()
    }

    func spawnLocal(
        request: ExecCommandRequest,
        sandboxType: SandboxType,
        env: [String: String],
        context: UnifiedExecContext
    ) async throws -> ProcessEntry {
        guard let program = request.command.first else {
            throw UnifiedExecError.missingCommandLine
        }
        let cwd: String
        do {
            cwd = try request.cwd.toAbsPath().asPath
        } catch {
            throw UnifiedExecError.foreignPath(path: request.cwd)
        }
        let args = Array(request.command.dropFirst())
        let preparedEnv = applyUnifiedExecEnv(env)
        let spawned: SpawnedProcess
        do {
            if request.tty {
                spawned = try await spawnPtyProcess(
                    program: program,
                    args: args,
                    cwd: cwd,
                    env: preparedEnv,
                    arg0: nil,
                    size: TerminalSize(),
                    inheritedFds: .attached([])
                )
            } else {
                spawned = try await spawnPipeProcess(
                    program: program,
                    args: args,
                    cwd: cwd,
                    env: preparedEnv
                )
            }
        } catch {
            throw UnifiedExecError.createProcess(String(describing: error))
        }
        let process = try await UnifiedExecProcess.fromSpawned(
            spawned,
            sandboxType: sandboxType,
            spawnLifecycle: NoopSpawnLifecycle()
        )
        evictIfNeeded()
        let entry = ProcessEntry(
            process: process,
            callId: context.callId,
            processId: request.processId,
            cwd: request.cwd,
            hookCommand: request.hookCommand,
            tty: request.tty,
            environmentId: "",
            permissions: TerminalPermissions.nativeDefault()
        )
        insert(entry)
        return entry
    }

    func writeStdin(_ request: WriteStdinRequest) async throws {
        guard let entry = process(for: request.processId) else {
            throw UnifiedExecError.unknownProcessId(processId: request.processId)
        }
        if request.input.isEmpty { return }
        if entry.process.hasExited() {
            throw UnifiedExecError.stdinClosed
        }
        do {
            try entry.process.write(Data(request.input.utf8))
        } catch {
            throw UnifiedExecError.writeToStdin
        }
        entry.lastUsed = .now
    }

    func collectOutput(_ process: UnifiedExecProcess, yieldTimeMs: UInt64) async -> Data {
        let budget = clampYieldTime(yieldTimeMs)
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await process.outputHandles().waitForOutput() }
            group.addTask {
                try? await Task.sleep(for: .milliseconds(Int64(budget)))
            }
            _ = await group.next()
            group.cancelAll()
        }
        return process.snapshotOutput()
    }
}
