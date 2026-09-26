//
//  process.swift
//  Sage
//
//  Port of codex-rs/core/src/unified_exec/process.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Local PTY/pipe path only. Exec-server transport is stubbed until that
//  crate is ported. Tokio watch/broadcast/Notify map to locks + continuations.
//

import CodexAsyncUtils
import CodexProtocol
import CodexSandboxing
import CodexUtils
import Foundation

let EARLY_EXIT_GRACE_PERIOD = Duration.milliseconds(150)

protocol SpawnLifecycle: AnyObject {
    func inheritedFds() -> [Int32]
    func afterSpawn()
}

typealias SpawnLifecycleHandle = SpawnLifecycle

final class NoopSpawnLifecycle: SpawnLifecycle {
    func inheritedFds() -> [Int32] { [] }
    func afterSpawn() {}
}

struct OutputBuffers {
    var pending = HeadTailBuffer()
    var transcript = HeadTailBuffer()

    mutating func pushChunk(_ chunk: Data) {
        pending.pushChunk(chunk)
        transcript.pushChunk(chunk)
    }
}

final class OutputHandles: @unchecked Sendable {
    let lock = NSLock()
    var outputBuffer = OutputBuffers()
    var outputClosed = false
    var waiters: [CheckedContinuation<Void, Never>] = []
    var closedWaiters: [CheckedContinuation<Void, Never>] = []
    let cancellationToken = CancellationToken()

    func notifyOutput() {
        let waiters = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            let current = self.waiters
            self.waiters.removeAll()
            return current
        }
        for waiter in waiters { waiter.resume() }
    }

    func notifyClosed() {
        let waiters = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            outputClosed = true
            let current = closedWaiters + self.waiters
            closedWaiters.removeAll()
            self.waiters.removeAll()
            return current
        }
        for waiter in waiters { waiter.resume() }
    }

    func waitForOutput() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            lock.lock()
            if outputClosed {
                lock.unlock()
                cont.resume()
                return
            }
            waiters.append(cont)
            lock.unlock()
        }
    }
}

final class UnifiedExecProcess: @unchecked Sendable {
    private enum Transport {
        case local(CodexUtils.ProcessHandle)
    }

    private var processHandle: Transport
    private let output = OutputHandles()
    private let stateLock = NSLock()
    private var state = ProcessState()
    private var outputTask: Task<Void, Never>?
    private var sandboxTypeValue: SandboxType?
    private var timedOutFlag = false
    private let spawnLifecycle: SpawnLifecycleHandle?
    private var subscribers: [(Data) -> Void] = []

    private init(
        processHandle: Transport,
        sandboxType: SandboxType?,
        spawnLifecycle: SpawnLifecycleHandle?
    ) {
        self.processHandle = processHandle
        self.sandboxTypeValue = sandboxType
        self.spawnLifecycle = spawnLifecycle
    }

    func write(_ data: Data) throws {
        switch processHandle {
        case .local(let handle):
            handle.writerSend(data)
        }
    }

    func outputHandles() -> OutputHandles { output }

    func subscribeOutput(_ handler: @escaping (Data) -> Void) {
        output.lock.lock()
        subscribers.append(handler)
        output.lock.unlock()
    }

    func cancellationToken() -> CancellationToken { output.cancellationToken }

    func hasExited() -> Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        switch processHandle {
        case .local(let handle):
            return state.hasExited || handle.hasExited()
        }
    }

    func exitCode() -> Int32? {
        if timedOut() { return 124 }
        stateLock.lock(); defer { stateLock.unlock() }
        switch processHandle {
        case .local(let handle):
            return state.exitCode ?? handle.exitCode()
        }
    }

    func markTimedOut() {
        stateLock.lock(); timedOutFlag = true; stateLock.unlock()
    }

    func timedOut() -> Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        return timedOutFlag
    }

    func terminate() {
        switch processHandle {
        case .local(let handle):
            handle.terminate()
        }
        finishTermination()
    }

    func terminateConfirmed() async throws {
        terminate()
        signalExit(exitCode())
    }

    func interrupt() throws {
        switch processHandle {
        case .local(let handle):
            try handle.signal(.interrupt)
        }
    }

    func failAndTerminate(_ message: String) {
        stateLock.lock()
        if state.failureMessage == nil {
            state = state.failed(message)
        }
        stateLock.unlock()
        terminate()
    }

    func sandboxType() -> SandboxType? { sandboxTypeValue }

    func failureMessage() -> String? {
        stateLock.lock(); defer { stateLock.unlock() }
        return state.failureMessage
    }

    func snapshotOutput() -> Data {
        output.lock.lock(); defer { output.lock.unlock() }
        return output.outputBuffer.pending.toBytes()
    }

    func checkForSandboxDenial() throws {
        let aggregated = snapshotOutput()
        let text = bytesToStringSmart(aggregated)
        try checkForSandboxDenial(text: text)
    }

    func checkForSandboxDenial(text: String) throws {
        stateLock.lock()
        let executorReportedDenial = state.sandboxDenied
        let exited = state.hasExited
        stateLock.unlock()
        let sandboxType = sandboxTypeValue ?? .none
        if !hasExited() || (!executorReportedDenial && sandboxType == .none) {
            return
        }
        let exitCode = exitCode() ?? -1
        let execOutput = ExecToolCallOutput(
            exitCode: exitCode,
            stderr: .new(text),
            aggregatedOutput: .new(text)
        )
        let likely = isLikelySandboxDenied(sandboxType: sandboxType, execOutput: execOutput)
        if likely {
            _ = recordFilesystemSandboxViolation(sandboxType: sandboxType, execOutput: execOutput)
        }
        if executorReportedDenial || likely {
            let snippet = formattedTruncateText(
                content: text,
                byteBudget: UNIFIED_EXEC_OUTPUT_MAX_TOKENS * 4
            )
            let message = snippet.isEmpty
                ? "Process exited with code \(exitCode)"
                : snippet
            throw UnifiedExecError.sandboxDenied(message, output: execOutput)
        }
        _ = exited
    }

    static func fromSpawned(
        _ spawned: SpawnedProcess,
        sandboxType: SandboxType,
        spawnLifecycle: SpawnLifecycleHandle
    ) async throws -> UnifiedExecProcess {
        let managed = UnifiedExecProcess(
            processHandle: .local(spawned.session),
            sandboxType: sandboxType,
            spawnLifecycle: spawnLifecycle
        )
        let combined = combineOutputReceivers(spawned.stdout, spawned.stderr)
        managed.outputTask = Task { [weak managed] in
            guard let managed else { return }
            for await chunk in combined {
                managed.output.lock.lock()
                managed.output.outputBuffer.pushChunk(chunk)
                let handlers = managed.subscribers
                managed.output.lock.unlock()
                for handler in handlers { handler(chunk) }
                managed.output.notifyOutput()
            }
            managed.output.notifyClosed()
        }
        let early = await withTaskGroup(of: Int32?.self) { group in
            group.addTask { await spawned.exit.value }
            group.addTask {
                try? await Task.sleep(for: EARLY_EXIT_GRACE_PERIOD)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        if let code = early {
            managed.signalExit(code)
            try managed.checkForSandboxDenial()
            return managed
        }
        Task { [weak managed] in
            let code = await spawned.exit.value
            managed?.signalExit(code)
        }
        spawnLifecycle.afterSpawn()
        return managed
    }

    private func finishTermination() {
        output.cancellationToken.cancel()
        outputTask?.cancel()
    }

    private func signalExit(_ exitCode: Int32?) {
        stateLock.lock()
        state = state.exited(exitCode)
        stateLock.unlock()
        output.cancellationToken.cancel()
    }

    deinit { terminate() }
}
