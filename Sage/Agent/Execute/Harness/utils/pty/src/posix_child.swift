//
//  posix_child.swift
//  CodexUtils
//
//  Port of codex-rs/utils/pty/src/posix_child.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  posix_spawn with POSIX_SPAWN_SETSID / addchdir_np. SIGCHLD wait replaces
//  Tokio unix signal stream.
//

import Darwin
import Foundation

private let POSIX_SPAWN_SETSID: Int16 = 0x0400

final class NativeChild {
    private var pid: pid_t?
    private var status: Int32?

    init(pid: pid_t) {
        self.pid = pid
    }

    func id() -> UInt32? {
        pid.map(UInt32.init)
    }

    func wait() async throws -> Int32 {
        if let status { return status }
        guard let pid else {
            throw NSError(domain: "CodexUtils.PTY", code: 4, userInfo: [
                NSLocalizedDescriptionKey: "child already transferred to reaper"
            ])
        }
        let code: Int32 = try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global().async {
                var waitStatus: Int32 = 0
                while waitpid(pid, &waitStatus, 0) < 0 {
                    if errno != EINTR {
                        cont.resume(throwing: posixError())
                        return
                    }
                }
                cont.resume(returning: exitCodeFromWaitStatus(waitStatus))
            }
        }
        status = code
        self.pid = nil
        return code
    }

    func kill() async throws {
        guard let pid else { return }
        if Darwin.kill(pid, SIGKILL) == -1 && errno != ESRCH {
            throw posixError()
        }
        _ = try await wait()
    }

    static func spawn(_ request: Command) throws -> Child? {
        let program = request.program
        if program.isEmpty { return nil }

        var stdinRead: Int32 = -1
        var stdinWrite: Int32 = -1
        var stdoutRead: Int32 = -1
        var stdoutWrite: Int32 = -1
        var stderrRead: Int32 = -1
        var stderrWrite: Int32 = -1
        func makePipe(_ read: inout Int32, _ write: inout Int32) throws {
            var fds = [Int32](repeating: 0, count: 2)
            if pipe(&fds) != 0 { throw posixError() }
            read = fds[0]
            write = fds[1]
        }
        switch request.stdin {
        case .piped:
            try makePipe(&stdinRead, &stdinWrite)
        case .null:
            stdinRead = open("/dev/null", O_RDONLY)
        case .file(let fd):
            stdinRead = fd
        }
        try makePipe(&stdoutRead, &stdoutWrite)
        try makePipe(&stderrRead, &stderrWrite)

        var actions = posix_spawn_file_actions_t(bitPattern: 0)
        posix_spawn_file_actions_init(&actions)
        posix_spawn_file_actions_adddup2(&actions, stdinRead, STDIN_FILENO)
        posix_spawn_file_actions_adddup2(&actions, stdoutWrite, STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&actions, stderrWrite, STDERR_FILENO)
        if let cwd = request.cwd {
            cwd.withCString { path in
                _ = posix_spawn_file_actions_addchdir_np(&actions, path)
            }
        }

        var attrs = posix_spawnattr_t(bitPattern: 0)
        posix_spawnattr_init(&attrs)
        if request.processMode == .newSession {
            posix_spawnattr_setflags(&attrs, POSIX_SPAWN_SETSID)
        }

        var pid: pid_t = 0
        let argv0 = request.arg0 ?? program
        var cArgs = ([argv0] + request.args).map { strdup($0) } + [nil]
        var cEnv = request.env.map { strdup("\($0.key)=\($0.value)") } + [nil]
        let status = program.withCString { path in
            posix_spawn(&pid, path, &actions, &attrs, &cArgs, &cEnv)
        }
        posix_spawn_file_actions_destroy(&actions)
        posix_spawnattr_destroy(&attrs)
        for ptr in cArgs where ptr != nil { free(ptr) }
        for ptr in cEnv where ptr != nil { free(ptr) }

        Darwin.close(stdinRead)
        Darwin.close(stdoutWrite)
        Darwin.close(stderrWrite)
        if status != 0 {
            Darwin.close(stdinWrite)
            Darwin.close(stdoutRead)
            Darwin.close(stderrRead)
            if request.fallback == .returnError {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(status), userInfo: nil)
            }
            return nil
        }
        if request.processMode == .newGroup {
            _ = setpgid(pid, pid)
        }

        return Child(
            native: NativeChild(pid: pid),
            stdin: stdinWrite >= 0 ? FileHandle(fileDescriptor: stdinWrite, closeOnDealloc: true) : nil,
            stdout: FileHandle(fileDescriptor: stdoutRead, closeOnDealloc: true),
            stderr: FileHandle(fileDescriptor: stderrRead, closeOnDealloc: true)
        )
    }
}

@_silgen_name("posix_spawn_file_actions_addchdir_np")
private func posix_spawn_file_actions_addchdir_np(
    _ actions: UnsafeMutablePointer<posix_spawn_file_actions_t?>,
    _ path: UnsafePointer<CChar>
) -> Int32
