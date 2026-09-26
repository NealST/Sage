//
//  maintenance.swift
//  CodexRollout
//
//  Port of codex-rs/rollout/src/maintenance.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  `File::try_lock` maps to `flock(2)` `LOCK_EX|LOCK_NB` on Darwin.
//

import CodexUtils
import Foundation

#if canImport(Darwin)
import Darwin
#endif

private let rolloutMaintenanceLock = "rollout-maintenance.lock"

/// Holds exclusive ownership of operations that replace local rollout files.
public final class RolloutMaintenanceGuard {
    private let file: FileHandle

    init(file: FileHandle) {
        self.file = file
    }

    deinit {
        try? file.close()
    }
}

/// Try to exclude rollout compression and migration for one Codex home.
public func tryAcquireRolloutMaintenanceLock(codexHome: String) throws -> RolloutMaintenanceGuard? {
    let directory = (codexHome as NSString).appendingPathComponent(".tmp")
    try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    let path = (directory as NSString).appendingPathComponent(rolloutMaintenanceLock)
    if !FileManager.default.fileExists(atPath: path) {
        FileManager.default.createFile(atPath: path, contents: nil)
    }
    let handle = try FileHandle(forUpdating: URL(fileURLWithPath: path))
#if canImport(Darwin)
    if flock(handle.fileDescriptor, LOCK_EX | LOCK_NB) == 0 {
        return RolloutMaintenanceGuard(file: handle)
    }
    let saved = errno
    try? handle.close()
    if saved == EWOULDBLOCK || saved == EAGAIN {
        return nil
    }
    throw IOError.fromErrno(saved, context: "flock")
#else
    try? handle.close()
    throw IOError.other("rollout maintenance locks require Darwin flock")
#endif
}
