//
//  writer_lock.swift
//  CodexRollout
//
//  Port of codex-rs/rollout/src/writer_lock.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  `std::fs::File::lock` / `try_lock` map to `flock(2)` on Darwin
//  (`LOCK_EX` / `LOCK_EX|LOCK_NB`). Coordination still serializes create
//  and stale-lock cleanup.
//

import CodexProtocol
import CodexUtils
import Foundation
import os

#if canImport(Darwin)
import Darwin
#endif

private let writerLockDir = "thread-writer-locks"
private let coordinationLockFile = ".coordination.lock"

/// Coordinates writer ownership within one Codex home.
public final class WriterLockCoordinator: @unchecked Sendable {
    private let directory: String
    private let cleanupAttempted = OSAllocatedUnfairLock(initialState: false)

    /// Uses the same lock namespace as existing local thread-store writers.
    public init(codexHome: String) {
        directory = (codexHome as NSString).appendingPathComponent(writerLockDir)
    }

    /// Acquires exclusive writer ownership, returning `WouldBlock` for an active writer.
    public func acquire(threadId: ThreadId) throws -> WriterLockGuard {
        let coordinationLock = try lockCoordination()
        defer { try? coordinationLock.close() }

        let alreadyCleaned = cleanupAttempted.withLock { attempted -> Bool in
            let previous = attempted
            attempted = true
            return previous
        }
        if !alreadyCleaned {
            do {
                try removeStaleThreadLocks()
            } catch {
                // Best-effort cleanup; an active writer still proceeds.
            }
        }

        let path = (directory as NSString).appendingPathComponent("\(threadId).lock")
        let handle: FileHandle
        do {
            if !FileManager.default.fileExists(atPath: path) {
                FileManager.default.createFile(atPath: path, contents: nil)
            }
            handle = try FileHandle(forUpdating: URL(fileURLWithPath: path))
        } catch {
            throw IOError.other("failed to open thread writer lock \(path): \(error)")
        }

        do {
            try applyExclusiveLock(handle.fileDescriptor, nonBlocking: true)
        } catch let error as IOError where error.kind == .wouldBlock {
            try? handle.close()
            throw IOError.wouldBlock("thread \(threadId) already has an active writer")
        } catch {
            try? handle.close()
            throw IOError.other("failed to acquire thread writer lock \(path): \(error)")
        }

        return WriterLockGuard(coordinator: self, path: path, file: handle)
    }

    /// Holds coordination through publication after probing that the thread is idle.
    func tryAcquireForPublication(threadId: ThreadId) throws -> FileHandle? {
        let coordinationLock = try lockCoordination()
        let path = (directory as NSString).appendingPathComponent("\(threadId).lock")
        do {
            let handle = try FileHandle(forUpdating: URL(fileURLWithPath: path))
            defer { try? handle.close() }
            do {
                try applyExclusiveLock(handle.fileDescriptor, nonBlocking: true)
                return coordinationLock
            } catch let error as IOError where error.kind == .wouldBlock {
                try? coordinationLock.close()
                return nil
            }
        } catch let error as NSError
            where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError
                || error.domain == NSPOSIXErrorDomain && error.code == Int(ENOENT)
        {
            return coordinationLock
        }
    }

    func lockCoordination() throws -> FileHandle {
        try FileManager.default.createDirectory(
            atPath: directory, withIntermediateDirectories: true)
        let path = (directory as NSString).appendingPathComponent(coordinationLockFile)
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: nil)
        }
        let handle = try FileHandle(forUpdating: URL(fileURLWithPath: path))
        do {
            try applyExclusiveLock(handle.fileDescriptor, nonBlocking: false)
        } catch {
            try? handle.close()
            throw IOError.other("failed to acquire thread writer coordination lock: \(error)")
        }
        return handle
    }

    private func removeStaleThreadLocks() throws {
        let entries = try FileManager.default.contentsOfDirectory(atPath: directory)
        for fileName in entries {
            guard let threadIdRaw = fileName.stripSuffix(".lock"),
                  (try? ThreadId.fromString(threadIdRaw)) != nil
            else { continue }

            let path = (directory as NSString).appendingPathComponent(fileName)
            let handle: FileHandle
            do {
                handle = try FileHandle(forUpdating: URL(fileURLWithPath: path))
            } catch let error as NSError
                where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError
                    || error.domain == NSPOSIXErrorDomain && error.code == Int(ENOENT)
            {
                continue
            } catch {
                continue
            }
            do {
                try applyExclusiveLock(handle.fileDescriptor, nonBlocking: true)
                try? handle.close()
                try? FileManager.default.removeItem(atPath: path)
            } catch let error as IOError where error.kind == .wouldBlock {
                try? handle.close()
            } catch {
                try? handle.close()
            }
        }
    }
}

/// Keeps a thread owned until all file work has finished.
public final class WriterLockGuard {
    private let coordinator: WriterLockCoordinator
    private let path: String
    private var file: FileHandle?

    init(coordinator: WriterLockCoordinator, path: String, file: FileHandle) {
        self.coordinator = coordinator
        self.path = path
        self.file = file
    }

    deinit {
        let coordinationLock: FileHandle
        do {
            coordinationLock = try coordinator.lockCoordination()
        } catch {
            return
        }
        if let file {
            try? file.close()
            self.file = nil
        }
        do {
            try FileManager.default.removeItem(atPath: path)
        } catch let error as NSError
            where error.domain == NSCocoaErrorDomain && error.code == NSFileNoSuchFileError
        {
        } catch {
        }
        try? coordinationLock.close()
    }
}

private func applyExclusiveLock(_ fd: Int32, nonBlocking: Bool) throws {
#if canImport(Darwin)
    let operation = LOCK_EX | (nonBlocking ? LOCK_NB : 0)
    if flock(fd, operation) == 0 { return }
    if nonBlocking && (errno == EWOULDBLOCK || errno == EAGAIN) {
        throw IOError.wouldBlock("lock would block")
    }
    throw IOError.fromErrno(errno, context: "flock")
#else
    throw IOError.other("writer locks require Darwin flock")
#endif
}

private extension String {
    func stripSuffix(_ suffix: String) -> String? {
        guard hasSuffix(suffix) else { return nil }
        return String(dropLast(suffix.count))
    }
}
