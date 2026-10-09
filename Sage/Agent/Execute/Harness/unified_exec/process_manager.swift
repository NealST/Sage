//
//  process_manager.swift
//  Sage
//
//  Port of codex-rs/core/src/unified_exec/process_manager.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Process-id allocation, env overlay, local spawn, and stdin approval
//  checks before write. HUD still owns the card; a needed review throws
//  instead of waiting inside `runTurn`. Plugin sidecar stays out.
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

    func writeStdin(
        _ request: WriteStdinRequest,
        current: PermissionProfile = .disabled,
        writeStdinApprovalEnabled: Bool = true,
        strictAutoReview: Bool = false,
        alreadyApproved: Bool = false
    ) async throws {
        guard let entry = process(for: request.processId) else {
            throw UnifiedExecError.unknownProcessId(processId: request.processId)
        }
        if !alreadyApproved {
            switch entry.stdinApproval(
                input: request.input,
                current: current,
                writeStdinApprovalEnabled: writeStdinApprovalEnabled,
                strictAutoReview: strictAutoReview
            ) {
            case .failure(let error):
                throw error
            case .success(let need):
                if let need {
                    throw UnifiedExecError.stdinApproval(need.reason)
                }
            }
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

    /// rust `UnifiedExecProcessManager::terminate_all_processes`.
    /// Network-approval unregistration waits.
    public func terminateAllProcesses() async {
        processStore.lock()
        let entries = Array(store.processes.values)
        store.processes.removeAll()
        store.reservedProcessIds.removeAll()
        processStore.unlock()
        for entry in entries {
            entry.process.terminate()
        }
    }

    public func processCount() -> Int {
        processStore.lock()
        defer { processStore.unlock() }
        return store.processes.count
    }

    public func reservedProcessIds() -> Set<Int32> {
        processStore.lock()
        defer { processStore.unlock() }
        return store.reservedProcessIds
    }

    public func reserveProcessId(_ processId: Int32) {
        processStore.lock()
        store.reservedProcessIds.insert(processId)
        processStore.unlock()
    }

    /// Records a spawned process in this thread's background-terminal store.
    public func trackSpawnedProcess(
        processId: Int32,
        callId: String,
        command: String,
        cwd: String,
        spawned: SpawnedProcess
    ) async throws -> BackgroundTerminalHandle {
        let process = try await UnifiedExecProcess.fromSpawned(
            spawned,
            sandboxType: .none,
            spawnLifecycle: NoopSpawnLifecycle()
        )
        let entry = ProcessEntry(
            process: process,
            callId: callId,
            processId: processId,
            cwd: PathUri(try AbsolutePathBuf.fromAbsolutePath(cwd)),
            hookCommand: command,
            tty: false,
            environmentId: "local",
            permissions: TerminalPermissions.nativeDefault()
        )
        processStore.lock()
        store.processes[processId] = entry
        store.reservedProcessIds.insert(processId)
        processStore.unlock()
        return BackgroundTerminalHandle(process)
    }
}

public final class BackgroundTerminalHandle: @unchecked Sendable {
    private let process: UnifiedExecProcess

    init(_ process: UnifiedExecProcess) {
        self.process = process
    }

    public func hasExited() -> Bool { process.hasExited() }

    public func terminate() { process.terminate() }
}
