//
//  ProcessRunner.swift
//  Sage
//
//  Cancellable process execution with timeout + cooperative Stop support.
//

import Foundation

nonisolated struct ProcessRunResult: Sendable {
    let exitCode: Int32
    let output: String
    let timedOut: Bool
}

/// Shared process lifecycle for shell / skill scripts.
/// Registered processes are terminated when the calling Task is cancelled or via `terminateAll()`.
nonisolated enum ProcessRunner {
    private static let lock = NSLock()
    private static var liveProcesses: [ObjectIdentifier: Process] = [:]

    /// Runs a process, collecting combined stdout/stderr.
    /// Honors Task cancellation (SIGTERM → brief grace → SIGKILL) and optional timeout.
    static func run(
        executable: URL,
        arguments: [String],
        currentDirectory: URL?,
        timeout: Duration?
    ) async throws -> ProcessRunResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        let buffer = LockedDataBuffer()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if !chunk.isEmpty {
                buffer.append(chunk)
            }
        }

        register(process)
        defer {
            pipe.fileHandleForReading.readabilityHandler = nil
            unregister(process)
        }

        do {
            try process.run()
        } catch {
            throw ToolError.operationFailed(
                "Failed to start process: \(error.localizedDescription)"
            )
        }

        let timedOut = try await withTaskCancellationHandler {
            try await waitForExit(process: process, timeout: timeout)
        } onCancel: {
            terminate(process)
        }

        // Drain remaining pipe bytes after exit.
        let remaining = pipe.fileHandleForReading.readDataToEndOfFile()
        if !remaining.isEmpty {
            buffer.append(remaining)
        }

        try Task.checkCancellation()

        let data = buffer.data
        let output = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .ascii)
            ?? "(binary output, \(data.count) bytes)"

        return ProcessRunResult(
            exitCode: process.terminationStatus,
            output: output,
            timedOut: timedOut
        )
    }

    /// Kill every process still registered (Stop / teardown).
    static func terminateAll() {
        lock.lock()
        let processes = Array(liveProcesses.values)
        lock.unlock()
        for process in processes {
            terminate(process)
        }
    }

    // MARK: - Internals

    private static func waitForExit(process: Process, timeout: Duration?) async throws -> Bool {
        try await withThrowingTaskGroup(of: Bool.self) { group in
            group.addTask {
                await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                    DispatchQueue.global(qos: .utility).async {
                        process.waitUntilExit()
                        cont.resume()
                    }
                }
                return false // completed
            }
            if let timeout {
                group.addTask {
                    try await Task.sleep(for: timeout)
                    return true // timed out
                }
            }

            let first = try await group.next()!
            group.cancelAll()
            if first {
                terminate(process)
                try? await Task.sleep(for: .milliseconds(100))
            }
            try Task.checkCancellation()
            return first
        }
    }

    private static func register(_ process: Process) {
        lock.lock()
        liveProcesses[ObjectIdentifier(process)] = process
        lock.unlock()
    }

    private static func unregister(_ process: Process) {
        lock.lock()
        liveProcesses.removeValue(forKey: ObjectIdentifier(process))
        lock.unlock()
    }

    private static func terminate(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 5) {
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }
    }
}

/// Thread-safe mutable data buffer for collecting pipe output.
nonisolated final class LockedDataBuffer: @unchecked Sendable {
    private var _data = Data()
    private let lock = NSLock()

    nonisolated func append(_ chunk: Data) {
        lock.lock()
        _data.append(chunk)
        lock.unlock()
    }

    nonisolated var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return _data
    }
}
