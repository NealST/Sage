//
//  process.swift
//  CodexUtils
//
//  Port of codex-rs/utils/pty/src/process.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  ProcessHandle / SpawnedProcess / TerminalSize. Tokio mpsc/oneshot/JoinHandle
//  become AsyncStream, Task, and an actor-like class. PTY resize uses
//  TIOCSWINSZ on the master fd.
//

import Darwin
import Foundation

public enum ProcessSignal: Equatable, Sendable {
    case interrupt
}

func unsupportedSignal(_ signal: ProcessSignal) -> NSError {
    NSError(
        domain: NSPOSIXErrorDomain,
        code: Int(ENOTSUP),
        userInfo: [NSLocalizedDescriptionKey: "process interrupt is not supported by this process backend"]
    )
}

func exitCodeFromWaitStatus(_ status: Int32) -> Int32 {
    if (status & 0x7f) == 0 {
        return (status >> 8) & 0xff
    }
    let signal = status & 0x7f
    if signal != 0 {
        return 128 + signal
    }
    return -1
}

protocol ChildTerminator: AnyObject {
    func signal(_ signal: ProcessSignal) throws
    func kill() throws
}

public struct TerminalSize: Equatable, Sendable {
    public var rows: UInt16
    public var cols: UInt16

    public init(rows: UInt16 = 24, cols: UInt16 = 80) {
        self.rows = rows
        self.cols = cols
    }
}

enum PtyMasterHandle {
    case resizable(Int32)
    case opaque(rawFd: Int32)
}

public final class ProcessHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var writer: ((Data) -> Void)?
    private var terminator: ChildTerminator?
    private var readerTasks: [Task<Void, Never>] = []
    private var writerTask: Task<Void, Never>?
    private var waitTask: Task<Void, Never>?
    private var exited = false
    private var code: Int32?
    private var masterFd: Int32?
    private var processGroupIdValue: UInt32?

    init(
        writer: @escaping (Data) -> Void,
        terminator: ChildTerminator,
        masterFd: Int32?,
        processGroupId: UInt32?,
        readerTasks: [Task<Void, Never>],
        writerTask: Task<Void, Never>?,
        waitTask: Task<Void, Never>?,
        exitStatus: @escaping () -> (Bool, Int32?)
    ) {
        self.writer = writer
        self.terminator = terminator
        self.masterFd = masterFd
        self.processGroupIdValue = processGroupId
        self.readerTasks = readerTasks
        self.writerTask = writerTask
        self.waitTask = waitTask
        _ = exitStatus
    }

    public func processGroupId() -> UInt32? {
        lock.lock(); defer { lock.unlock() }
        return processGroupIdValue
    }

    func bindExit(exited: Bool, code: Int32?) {
        lock.lock()
        self.exited = exited
        self.code = code
        lock.unlock()
    }

    public func writerSend(_ bytes: Data) {
        lock.lock()
        let writer = self.writer
        lock.unlock()
        writer?(bytes)
    }

    public func hasExited() -> Bool {
        lock.lock(); defer { lock.unlock() }
        return exited
    }

    public func exitCode() -> Int32? {
        lock.lock(); defer { lock.unlock() }
        return code
    }

    public func resize(_ size: TerminalSize) throws {
        lock.lock()
        let fd = masterFd
        lock.unlock()
        guard let fd else {
            throw NSError(
                domain: "CodexUtils.PTY",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "process is not attached to a PTY"]
            )
        }
        try resizeRawPty(fd, size)
    }

    public func closeStdin() {
        lock.lock()
        writer = nil
        lock.unlock()
    }

    public func requestTerminate() {
        lock.lock()
        let killer = terminator
        terminator = nil
        lock.unlock()
        try? killer?.kill()
    }

    public func signal(_ signal: ProcessSignal) throws {
        lock.lock()
        let killer = terminator
        lock.unlock()
        guard let killer else { return }
        try killer.signal(signal)
    }

    public func terminate() {
        requestTerminate()
        lock.lock()
        let readers = readerTasks
        readerTasks.removeAll()
        let writer = writerTask
        writerTask = nil
        lock.unlock()
        for task in readers { task.cancel() }
        writer?.cancel()
    }

    deinit { terminate() }
}

public struct SpawnedProcess: @unchecked Sendable {
    public var session: ProcessHandle
    public var stdout: AsyncStream<Data>
    public var stderr: AsyncStream<Data>
    public var exit: Task<Int32, Never>
    public var processGroupId: UInt32?
}

public func combineOutputReceivers(
    _ stdout: AsyncStream<Data>,
    _ stderr: AsyncStream<Data>
) -> AsyncStream<Data> {
    AsyncStream { continuation in
        let task = Task {
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    for await chunk in stdout { continuation.yield(chunk) }
                }
                group.addTask {
                    for await chunk in stderr { continuation.yield(chunk) }
                }
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
    }
}

func resizeRawPty(_ rawFd: Int32, _ size: TerminalSize) throws {
    var winsize = winsize(ws_row: size.rows, ws_col: size.cols, ws_xpixel: 0, ws_ypixel: 0)
    if ioctl(rawFd, UInt(TIOCSWINSZ), &winsize) == -1 {
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: nil)
    }
}

final class ProcessGroupTerminator: ChildTerminator {
    let processGroupId: UInt32

    init(_ processGroupId: UInt32) {
        self.processGroupId = processGroupId
    }

    func signal(_ signal: ProcessSignal) throws {
        switch signal {
        case .interrupt:
            try interruptProcessGroup(processGroupId)
        }
    }

    func kill() throws {
        try killProcessGroup(processGroupId)
    }
}
