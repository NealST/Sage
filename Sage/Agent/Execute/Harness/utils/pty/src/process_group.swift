//
//  process_group.swift
//  CodexUtils
//
//  Port of codex-rs/utils/pty/src/process_group.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  macOS path: denied group signals retry against `proc_listpgrppids` members.
//  `set_parent_death_signal` is a no-op (Linux prctl).
//

import Darwin
import Foundation

public func setParentDeathSignal(_ parentPid: Int32) throws {
    _ = parentPid
}

public func detachFromTty() throws {
    if setsid() == -1 {
        if errno == EPERM {
            try setProcessGroup()
            return
        }
        throw posixError()
    }
}

public func setProcessGroup() throws {
    if setpgid(0, 0) == -1 { throw posixError() }
}

public func killProcessGroupByPid(_ pid: UInt32) throws {
    let pid = pid_t(pid)
    let pgid = getpgid(pid)
    if pgid == -1 {
        if errno == ESRCH { return }
        throw posixError()
    }
    if killpg(pgid, SIGKILL) == -1 {
        if errno == ESRCH { return }
        throw posixError()
    }
}

public func terminateProcessGroup(_ processGroupId: UInt32) throws -> Bool {
    try signalProcessGroupWithMemberFallback(processGroupId, SIGTERM)
}

public func interruptProcessGroup(_ processGroupId: UInt32) throws {
    _ = try signalProcessGroupId(pid_t(processGroupId), SIGINT)
}

public func killProcessGroup(_ processGroupId: UInt32) throws {
    _ = try signalProcessGroupWithMemberFallback(processGroupId, SIGKILL)
}

public func killChildProcessGroup(_ pid: UInt32?) throws {
    guard let pid else { return }
    try killProcessGroupByPid(pid)
}

private func signalProcessGroupId(_ pgid: pid_t, _ signal: Int32) throws -> Bool {
    if killpg(pgid, signal) == -1 {
        if errno == ESRCH { return false }
        throw posixError()
    }
    return true
}

private func signalProcessId(_ pid: pid_t, _ signal: Int32) throws -> Bool {
    if kill(pid, signal) == -1 {
        if errno == ESRCH { return false }
        throw posixError()
    }
    return true
}

private func signalProcessGroupWithMemberFallback(_ processGroupId: UInt32, _ signal: Int32) throws -> Bool {
    guard processGroupId > 0 else {
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(EINVAL), userInfo: [
            NSLocalizedDescriptionKey: "invalid process group ID"
        ])
    }
    let pgid = pid_t(processGroupId)
    do {
        return try signalProcessGroupId(pgid, signal)
    } catch {
        let ns = error as NSError
        if ns.domain != NSPOSIXErrorDomain || ns.code != Int(EPERM) {
            throw error
        }
    }

    var processIds = [pid_t](repeating: 0, count: 16)
    while true {
        let bufferSize = Int32(MemoryLayout<pid_t>.stride * processIds.count)
        let count = processIds.withUnsafeMutableBufferPointer { buf in
            proc_listpgrppids(pgid, buf.baseAddress, bufferSize)
        }
        if count < 0 { throw posixError() }
        if Int(count) < processIds.count {
            processIds = Array(processIds.prefix(Int(count)))
            break
        }
        processIds = [pid_t](repeating: 0, count: processIds.count * 2)
    }
    processIds.sort { lhs, rhs in
        (lhs == pgid ? 1 : 0) < (rhs == pgid ? 1 : 0)
    }

    var signalled = false
    var firstError: Error?
    for processId in processIds where processId > 0 {
        let current = getpgid(processId)
        if current == -1 {
            if errno != ESRCH && firstError == nil { firstError = posixError() }
            continue
        }
        if current != pgid { continue }
        do {
            signalled = try signalProcessId(processId, signal) || signalled
        } catch {
            if firstError == nil { firstError = error }
        }
    }
    if signalled { return true }
    if let firstError { throw firstError }
    return false
}

func posixError() -> NSError {
    NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: nil)
}
