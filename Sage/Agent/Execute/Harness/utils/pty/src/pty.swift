//
//  pty.swift
//  CodexUtils
//
//  Port of codex-rs/utils/pty/src/pty.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  macOS `openpty` + `fork`/`exec` path. portable-pty and the Linux spawn
//  helper are not used. Inherited-fd cleanup uses `proc_pidinfo`.
//

import Darwin
import Foundation

public enum ChildFds {
    case inherited([Int32])
    case attached([Int32])

    public func asSlice() -> [Int32] {
        switch self {
        case .inherited(let fds), .attached(let fds): return fds
        }
    }
}

public func conptySupported() -> Bool { true }

public func spawnPtyProcess(
    program: String,
    args: [String],
    cwd: String,
    env: [String: String],
    arg0: String?,
    size: TerminalSize,
    inheritedFds: ChildFds
) async throws -> SpawnedProcess {
    if program.isEmpty {
        throw NSError(domain: "CodexUtils.PTY", code: 2, userInfo: [
            NSLocalizedDescriptionKey: "missing program for PTY spawn"
        ])
    }
    return try spawnProcessPreservingFds(
        program: program,
        args: args,
        cwd: cwd,
        env: env,
        arg0: arg0,
        size: size,
        descriptors: inheritedFds
    )
}

public func spawnProcess( // rust `pty::spawn_process`
    program: String,
    args: [String],
    cwd: String,
    env: [String: String],
    arg0: String? = nil,
    size: TerminalSize = TerminalSize(),
    inheritedFds: ChildFds = .attached([])
) async throws -> SpawnedProcess {
    try await spawnPtyProcess(
        program: program,
        args: args,
        cwd: cwd,
        env: env,
        arg0: arg0,
        size: size,
        inheritedFds: inheritedFds
    )
}

private func spawnProcessPreservingFds(
    program: String,
    args: [String],
    cwd: String,
    env: [String: String],
    arg0: String?,
    size: TerminalSize,
    descriptors: ChildFds
) throws -> SpawnedProcess {
    let (master, slave) = try openUnixPty(size)
    let io = try PtyIo(masterFd: master)
    let usesPortableStatus: Bool
    switch descriptors {
    case .inherited(let fds): usesPortableStatus = fds.isEmpty
    case .attached: usesPortableStatus = true
    }
    let inherited = descriptors.asSlice()
    let stdinClose: StdinCloseBehavior = usesPortableStatus ? .sendEof : .noEof

    let pid = sysFork()
    if pid < 0 {
        Darwin.close(master)
        Darwin.close(slave)
        throw posixError()
    }
    if pid == 0 {
        Darwin.close(master)
        _ = dup2(slave, STDIN_FILENO)
        _ = dup2(slave, STDOUT_FILENO)
        _ = dup2(slave, STDERR_FILENO)
        if slave > STDERR_FILENO { Darwin.close(slave) }
        _ = try? configureChildTerminal()
        closeInheritedFdsExcept(inherited)
        _ = try? makeFdsInheritable(inherited)
        if chdir(cwd) != 0 { _exit(127) }
        execveProgram(program, args: args, arg0: arg0, env: env)
        _exit(127)
    }
    Darwin.close(slave)

    var stdoutCont: AsyncStream<Data>.Continuation!
    let stdout = AsyncStream<Data> { stdoutCont = $0 }
    var writerCont: AsyncStream<Data>.Continuation!
    let writer = AsyncStream<Data> { writerCont = $0 }
    let (_, _) = io.spawn(stdout: stdoutCont, writer: writer, stdinClose: stdinClose)

    let (exitTask, handle) = makeSpawnedHandle(
        pid: pid,
        masterFd: master,
        writer: { writerCont.yield($0) },
        stdout: stdout,
        closeWriter: { writerCont.finish() }
    )
    _ = usesPortableStatus
    return SpawnedProcess(
        session: handle,
        stdout: stdout,
        stderr: AsyncStream { $0.finish() },
        exit: exitTask,
        processGroupId: UInt32(pid)
    )
}

func openUnixPty(_ size: TerminalSize) throws -> (Int32, Int32) {
    var master: Int32 = -1
    var slave: Int32 = -1
    var win = winsize(ws_row: size.rows, ws_col: size.cols, ws_xpixel: 0, ws_ypixel: 0)
    if openpty(&master, &slave, nil, nil, &win) != 0 {
        throw posixError()
    }
    try setCloexec(master)
    try setCloexec(slave)
    return (master, slave)
}

func setCloexec(_ fd: Int32) throws {
    let flags = fcntl(fd, F_GETFD)
    if flags == -1 || fcntl(fd, F_SETFD, flags | FD_CLOEXEC) == -1 {
        throw posixError()
    }
}

public func makeFdsInheritable(_ fds: [Int32]) throws {
    for fd in fds {
        let flags = fcntl(fd, F_GETFD)
        if flags == -1 || fcntl(fd, F_SETFD, flags & ~FD_CLOEXEC) == -1 {
            throw posixError()
        }
    }
}

public func closeInheritedFdsExcept(_ preserved: [Int32]) {
    var descriptors = [proc_fdinfo](repeating: proc_fdinfo(), count: 1024)
    let bytes = descriptors.withUnsafeMutableBytes { buf in
        proc_pidinfo(getpid(), PROC_PIDLISTFDS, 0, buf.baseAddress, Int32(buf.count))
    }
    let closeInheritable: (Int32) -> Void = { fd in
        if fd <= STDERR_FILENO || preserved.contains(fd) { return }
        let flags = fcntl(fd, F_GETFD)
        if flags >= 0 && (flags & FD_CLOEXEC) == 0 {
            Darwin.close(fd)
        }
    }
    if bytes > 0 && Int(bytes) < MemoryLayout<proc_fdinfo>.stride * descriptors.count {
        let count = Int(bytes) / MemoryLayout<proc_fdinfo>.stride
        for i in 0..<count {
            closeInheritable(descriptors[i].proc_fd)
        }
        return
    }
    var limit = rlimit()
    if getrlimit(RLIMIT_NOFILE, &limit) == 0 {
        let upper = min(Int32(limit.rlim_cur), Int32.max)
        for fd in (STDERR_FILENO + 1)..<upper {
            closeInheritable(fd)
        }
    }
}

public func configureChildTerminal() throws {
    signal(SIGCHLD, SIG_DFL)
    signal(SIGHUP, SIG_DFL)
    signal(SIGINT, SIG_DFL)
    signal(SIGQUIT, SIG_DFL)
    signal(SIGTERM, SIG_DFL)
    signal(SIGALRM, SIG_DFL)
    var empty = sigset_t()
    sigemptyset(&empty)
    sigprocmask(SIG_SETMASK, &empty, nil)
    if setsid() == -1 { throw posixError() }
    if ioctl(0, UInt(TIOCSCTTY), 0) == -1 { throw posixError() }
}

func execveProgram(_ program: String, args: [String], arg0: String?, env: [String: String]) {
    let argv0 = arg0 ?? program
    var cArgs = ([argv0] + args).map { strdup($0) } + [nil]
    var cEnv = env.map { strdup("\($0.key)=\($0.value)") } + [nil]
    _ = program.withCString { path in
        sysExecve(path, &cArgs, &cEnv)
    }
}

@_silgen_name("fork")
private func sysFork() -> pid_t

@_silgen_name("execve")
private func sysExecve(
    _ path: UnsafePointer<CChar>,
    _ argv: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>,
    _ envp: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>
) -> Int32

func makeSpawnedHandle(
    pid: pid_t,
    masterFd: Int32?,
    writer: @escaping (Data) -> Void,
    stdout: AsyncStream<Data>,
    closeWriter: @escaping () -> Void
) -> (Task<Int32, Never>, ProcessHandle) {
    let exitBox = ExitBox()
    let waitTask = Task<Int32, Never> {
        var status: Int32 = 0
        while waitpid(pid, &status, 0) < 0 && errno == EINTR {}
        let code = exitCodeFromWaitStatus(status)
        exitBox.store(code)
        closeWriter()
        return code
    }
    let handle = ProcessHandle(
        writer: writer,
        terminator: ProcessGroupTerminator(UInt32(pid)),
        masterFd: masterFd,
        processGroupId: UInt32(pid),
        readerTasks: [],
        writerTask: nil,
        waitTask: Task { _ = await waitTask.value },
        exitStatus: { (exitBox.exited, exitBox.code) }
    )
    Task {
        let code = await waitTask.value
        handle.bindExit(exited: true, code: code)
    }
    _ = stdout
    return (waitTask, handle)
}

private final class ExitBox: @unchecked Sendable {
    private let lock = NSLock()
    var exited = false
    var code: Int32?
    func store(_ value: Int32) {
        lock.lock(); exited = true; code = value; lock.unlock()
    }
}
