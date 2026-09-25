//
//  spawn.swift
//  Sage
//
//  Port of codex-rs/core/src/spawn.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Request types and env-var contract match upstream. Process launch uses
//  Foundation `Process` instead of tokio + `utils/pty` pre_exec hooks
//  (detach_from_tty / close inherited fds). Those land with the pty crate.
//

import CodexProtocol
import CodexSandboxing
import CodexUtils
import Foundation

public let CODEX_SANDBOX_NETWORK_DISABLED_ENV_VAR = "CODEX_SANDBOX_NETWORK_DISABLED"
public let CODEX_SANDBOX_ENV_VAR = "CODEX_SANDBOX"

public enum StdioPolicy: Equatable, Sendable {
    case redirectForShellTool
    case inherit
}

struct SpawnChildRequest {
    var program: String
    var args: [String]
    var arg0: String?
    var cwd: AbsolutePathBuf
    var networkSandboxPolicy: NetworkSandboxPolicy
    var network: NetworkProxy?
    var stdioPolicy: StdioPolicy
    var env: [String: String]
}

func spawnChild(_ request: SpawnChildRequest) throws -> Process {
    var env = request.env
    env = env.filter { !isNonInheritableEnvVar($0.key) }
    if let network = request.network {
        try network.applyToEnvForOptionalEnvironment(&env, environmentId: nil)
    }
    if !request.networkSandboxPolicy.isEnabled {
        env[CODEX_SANDBOX_NETWORK_DISABLED_ENV_VAR] = "1"
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: request.program)
    process.arguments = request.args
    process.currentDirectoryURL = URL(fileURLWithPath: request.cwd.asPath)
    process.environment = env
    switch request.stdioPolicy {
    case .redirectForShellTool:
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = Pipe()
        process.standardError = Pipe()
    case .inherit:
        break
    }
    try process.run()
    return process
}
