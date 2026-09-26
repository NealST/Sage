//
//  spawn.swift
//  Sage
//
//  Port of codex-rs/core/src/spawn.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Request types and env-var contract match upstream. Launch goes through
//  `utils/pty` pipe spawn. macOS inherited-fd cleanup and `setpgid` live in
//  that crate; Linux `prctl` parent-death is excluded(platform).
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

func spawnChild(_ request: SpawnChildRequest) async throws -> SpawnedProcess {
    var env = request.env
    env = env.filter { !isNonInheritableEnvVar($0.key) }
    if let network = request.network {
        try network.applyToEnvForOptionalEnvironment(&env, environmentId: nil)
    }
    if !request.networkSandboxPolicy.isEnabled {
        env[CODEX_SANDBOX_NETWORK_DISABLED_ENV_VAR] = "1"
    }

    switch request.stdioPolicy {
    case .redirectForShellTool:
        return try await spawnPipeProcessNoStdin(
            program: request.program,
            args: request.args,
            cwd: request.cwd.asPath,
            env: env,
            arg0: request.arg0
        )
    case .inherit:
        return try await spawnPipeProcess(
            program: request.program,
            args: request.args,
            cwd: request.cwd.asPath,
            env: env,
            arg0: request.arg0
        )
    }
}
