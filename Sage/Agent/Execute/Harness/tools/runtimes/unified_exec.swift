//
//  unified_exec.swift
//  ToolsRuntimes
//
//  Port of codex-rs/core/src/tools/runtimes/unified_exec.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Orchestrator / Session spawn wait for Phase 5. This runtime prepares
//  the command environment and optional zsh-fork launch.
//

import CodexProtocol
import Foundation

public struct UnifiedExecRuntimeRequest: Equatable, Sendable {
    public var command: [String]
    public var cwd: URL
    public var env: [String: String]
    public var sandboxPermissions: SandboxPermissions
    public var tty: Bool
    public var yieldTimeMs: UInt64

    public init(
        command: [String],
        cwd: URL,
        env: [String: String] = [:],
        sandboxPermissions: SandboxPermissions = .useDefault,
        tty: Bool = false,
        yieldTimeMs: UInt64 = 10_000
    ) {
        self.command = command
        self.cwd = cwd
        self.env = env
        self.sandboxPermissions = sandboxPermissions
        self.tty = tty
        self.yieldTimeMs = yieldTimeMs
    }
}

public struct UnifiedExecPreparedSpawn: Equatable, Sendable {
    public var command: [String]
    public var env: [String: String]
    public var usedZshFork: Bool
}

public enum UnifiedExecRuntime {
    public static func prepare(_ request: UnifiedExecRuntimeRequest) -> UnifiedExecPreparedSpawn {
        var env = execEnvForSandboxPermissions(
            request.env,
            sandboxPermissions: request.sandboxPermissions
        )
        var command = request.command
        var usedZshFork = false
        if let prepared = maybePrepareUnifiedExec(command: command, env: &env) {
            command = prepared.command
            usedZshFork = true
        }
        return UnifiedExecPreparedSpawn(command: command, env: env, usedZshFork: usedZshFork)
    }
}
