//
//  child_command.swift
//  CodexUtils
//
//  Port of codex-rs/utils/pty/src/child_command.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Explicit launch settings. Native spawn uses posix_spawn / fork; there is
//  no Tokio Command wrapper.
//

import Darwin
import Foundation

public enum ProcessMode: Equatable, Sendable {
    case inherit
    case newGroup
    case newSession
}

public enum DescriptorPolicy: Equatable, Sendable {
    case inherit
    case explicit
}

public enum SpawnFallback: Equatable, Sendable {
    case compatible
    case returnError
}

enum ChildDropPolicy {
    case killAndReap
    case reapOnly
}

public enum PtyChildStdin {
    case piped
    case null
    case file(Int32)
}

public final class Command {
    public var program: String
    public var args: [String] = []
    public var env: [String: String] = [:]
    public var cwd: String?
    public var processMode: ProcessMode = .inherit
    public var descriptorPolicy: DescriptorPolicy = .inherit
    public var fallback: SpawnFallback = .compatible
    public var stdin: PtyChildStdin = .piped
    var dropPolicy: ChildDropPolicy = .killAndReap
    var inheritedFds: [Int32] = []
    var stdoutFile: Int32?
    var stderrFile: Int32?
    var arg0: String?
    var sawNul = false

    public init(_ program: String) {
        self.program = program
        sawNul = program.contains("\0")
    }

    @discardableResult
    public func arg(_ arg: String) -> Command {
        sawNul = sawNul || arg.contains("\0")
        args.append(arg)
        return self
    }

    @discardableResult
    public func args(_ args: [String]) -> Command {
        for arg in args { self.arg(arg) }
        return self
    }

    @discardableResult
    public func env(_ key: String, _ value: String) -> Command {
        env[key] = value
        return self
    }

    @discardableResult
    public func envs(_ env: [String: String]) -> Command {
        for (key, value) in env { self.env[key] = value }
        return self
    }

    @discardableResult
    public func currentDir(_ cwd: String) -> Command {
        sawNul = sawNul || cwd.contains("\0")
        self.cwd = cwd
        return self
    }

    @discardableResult
    public func processMode(_ mode: ProcessMode) -> Command {
        processMode = mode
        return self
    }

    @discardableResult
    func dropPolicy(_ policy: ChildDropPolicy) -> Command {
        dropPolicy = policy
        return self
    }

    @discardableResult
    public func stdin(_ stdin: PtyChildStdin) -> Command {
        self.stdin = stdin
        return self
    }

    @discardableResult
    public func descriptorPolicy(_ policy: DescriptorPolicy) -> Command {
        descriptorPolicy = policy
        return self
    }

    @discardableResult
    public func fallback(_ fallback: SpawnFallback) -> Command {
        self.fallback = fallback
        return self
    }

    @discardableResult
    public func preserveFds(_ fds: [Int32]) -> Command {
        inheritedFds = fds.filter { fd in
            let flags = fcntl(fd, F_GETFD)
            return fd > STDERR_FILENO && flags >= 0 && (flags & FD_CLOEXEC) == 0
        }
        return self
    }

    @discardableResult
    func inheritFds(_ fds: [Int32]) -> Command {
        inheritedFds = fds
        return self
    }

    @discardableResult
    public func arg0(_ arg0: String) -> Command {
        sawNul = sawNul || arg0.contains("\0")
        self.arg0 = arg0
        return self
    }

    func validate() throws {
        if sawNul {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(EINVAL), userInfo: [
                NSLocalizedDescriptionKey: "nul byte found in provided data"
            ])
        }
    }

    public func spawn() throws -> Child {
        try validate()
        if let child = try NativeChild.spawn(self) {
            return child
        }
        throw NSError(domain: "CodexUtils.PTY", code: 3, userInfo: [
            NSLocalizedDescriptionKey: "native spawn unavailable"
        ])
    }
}
