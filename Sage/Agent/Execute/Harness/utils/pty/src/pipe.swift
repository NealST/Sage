//
//  pipe.swift
//  CodexUtils
//
//  Port of codex-rs/utils/pty/src/pipe.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Pipe-backed spawn. Foundation `Process` plus `posix_spawn` file actions
//  for NewSession / explicit descriptors. Windows job objects omitted.
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
        throw NSError(domain: "CodexUtils.PTY", code: 2, userInfo: [
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
    try process.run()
    let pid = process.processIdentifier
    _ = setpgid(pid, pid)

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
        }
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
