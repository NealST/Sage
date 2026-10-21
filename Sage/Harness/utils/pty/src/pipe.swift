//
//  pipe.swift
//  SageUtils
//
//  Port of codex-rs/utils/pty/src/pipe.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Pipe-backed spawn. Foundation `Process` owns the child. The child
//  inherits ignored terminal-stop signals so `setpgid` does not freeze a
//  login shell. Windows job objects omitted.
//

import Darwin
import Foundation

public func spawnPipeProcess(
    program: String,
    args: [String],
    cwd: String,
    env: [String: String],
    arg0: String? = nil,
    inheritedFds: [Int32] = []
) async throws -> SpawnedProcess {
    try spawnProcessWithStdinMode(
        program: program,
        args: args,
        cwd: cwd,
        env: env,
        arg0: arg0,
        stdinNull: false,
        inheritedFds: inheritedFds
    )
}

public func spawnPipeProcessNoStdin(
    program: String,
    args: [String],
    cwd: String,
    env: [String: String],
    arg0: String? = nil,
    inheritedFds: [Int32] = []
) async throws -> SpawnedProcess {
    try spawnProcessWithStdinMode(
        program: program,
        args: args,
        cwd: cwd,
        env: env,
        arg0: arg0,
        stdinNull: true,
        inheritedFds: inheritedFds
    )
}

private func spawnProcessWithStdinMode(
    program: String,
    args: [String],
    cwd: String,
    env: [String: String],
    arg0: String?,
    stdinNull: Bool,
    inheritedFds: [Int32]
) throws -> SpawnedProcess {
    if program.isEmpty {
        throw NSError(domain: "SageUtils.PTY", code: 2, userInfo: [
            NSLocalizedDescriptionKey: "missing program for pipe spawn"
        ])
    }

    let stdinPipe = Pipe()
    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    if stdinNull {
        stdinPipe.fileHandleForWriting.closeFile()
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: program)
    process.arguments = args
    process.currentDirectoryURL = URL(fileURLWithPath: cwd)
    process.environment = env
    process.standardInput = stdinNull ? FileHandle.nullDevice : stdinPipe
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe
    let exitBox = PipeExitBox(process)
    let previousOutputStop = signal(SIGTTOU, SIG_IGN)
    let previousInputStop = signal(SIGTTIN, SIG_IGN)
    try process.run()
    _ = signal(SIGTTOU, previousOutputStop)
    _ = signal(SIGTTIN, previousInputStop)
    let pid = process.processIdentifier
    _ = setpgid(pid, pid)
    exitBox.watch()

    var stdoutCont: AsyncStream<Data>.Continuation!
    let stdout = AsyncStream<Data> { stdoutCont = $0 }
    var stderrCont: AsyncStream<Data>.Continuation!
    let stderr = AsyncStream<Data> { stderrCont = $0 }

    stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
        let data = handle.availableData
        if data.isEmpty {
            handle.readabilityHandler = nil
            stdoutCont.finish()
        } else {
            stdoutCont.yield(data)
        }
    }
    stderrPipe.fileHandleForReading.readabilityHandler = { handle in
        let data = handle.availableData
        if data.isEmpty {
            handle.readabilityHandler = nil
            stderrCont.finish()
        } else {
            stderrCont.yield(data)
        }
    }

    let writer: (Data) -> Void = { data in
        try? stdinPipe.fileHandleForWriting.write(contentsOf: data)
    }
    let (exitTask, handle) = makeSpawnedHandle(
        pid: pid,
        masterFd: nil,
        writer: writer,
        stdout: stdout,
        closeWriter: {
            try? stdinPipe.fileHandleForWriting.close()
        },
        exitTask: Task.detached(priority: .userInitiated) { await exitBox.wait() }
    )
    _ = inheritedFds
    _ = arg0
    return SpawnedProcess(
        session: handle,
        stdout: stdout,
        stderr: stderr,
        exit: exitTask,
        processGroupId: UInt32(pid)
    )
}

private final class PipeExitBox: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Int32, Never>?
    private var status: Int32?
    private var finished = false
    private let process: Process

    init(_ process: Process) {
        self.process = process
    }

    func watch() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            self.process.waitUntilExit()
            self.finish(self.process.terminationStatus)
        }
    }

    func wait() async -> Int32 {
        await withCheckedContinuation { continuation in
            lock.lock()
            if let status {
                lock.unlock()
                continuation.resume(returning: status)
                return
            }
            self.continuation = continuation
            lock.unlock()
        }
    }

    private func finish(_ status: Int32) {
        lock.lock()
        if finished {
            lock.unlock()
            return
        }
        finished = true
        let continuation = self.continuation
        if continuation == nil { self.status = status }
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: status)
    }
}
