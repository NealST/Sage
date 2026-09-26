//
//  mod.swift
//  ToolsRuntimes
//
//  Port of codex-rs/core/src/tools/runtimes/mod.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Session / plugin / network-proxy process env wait for later phases.
//  PATH prepend and sandbox-permission env cleanup are Session-free.
//

import CodexProtocol
import Foundation

public let SNAPSHOT_ORIGINAL_BASH_ENV_ENV_KEY = "CODEX_NETWORK_PROXY_SNAPSHOT_ORIGINAL_BASH_ENV"
public let SNAPSHOT_ORIGINAL_POSIX_ENV_ENV_KEY = "CODEX_NETWORK_PROXY_SNAPSHOT_ORIGINAL_POSIX_ENV"
public let SNAPSHOT_ORIGINAL_ZDOTDIR_ENV_KEY = "CODEX_NETWORK_PROXY_SNAPSHOT_ORIGINAL_ZDOTDIR"
public let SNAPSHOT_BROKERED_VALUE_ENV_PREFIX = "CODEX_NETWORK_PROXY_SNAPSHOT_BROKERED_VALUE_"
public let SNAPSHOT_BROKERED_UNSET_ENV_PREFIX = "CODEX_NETWORK_PROXY_SNAPSHOT_BROKERED_UNSET_"
public let PROXY_ACTIVE_ENV_KEY = "CODEX_NETWORK_PROXY_ACTIVE"

public func execEnvForSandboxPermissions(
    _ env: [String: String],
    sandboxPermissions: SandboxPermissions
) -> [String: String] {
    var env = env
    if sandboxPermissions.requiresEscalatedPermissions, env[PROXY_ACTIVE_ENV_KEY] != nil {
        env = stripManagedProxyEnv(env)
    }
    return env
}

public func stripManagedProxyEnv(_ env: [String: String]) -> [String: String] {
    env.filter { key, _ in
        !key.hasPrefix("CODEX_NETWORK_PROXY_") && key != PROXY_ACTIVE_ENV_KEY
    }
}

@discardableResult
public func prependPathEntry(_ env: inout [String: String], pathEntry: String) -> String? {
    if pathEntry.isEmpty { return nil }
    let updated: String
    if let path = env["PATH"], !path.isEmpty {
        updated = ([pathEntry] + path.split(separator: ":").map(String.init).filter { !$0.isEmpty && $0 != pathEntry })
            .joined(separator: ":")
    } else {
        updated = pathEntry
    }
    env["PATH"] = updated
    return updated
}

public struct RuntimePathPrepends: Equatable, Sendable {
    public var entries: [String] = []

    public init() {}

    public mutating func prepend(_ env: inout [String: String], pathEntry: String) {
        if prependPathEntry(&env, pathEntry: pathEntry) != nil {
            entries.removeAll { $0 == pathEntry }
            entries.append(pathEntry)
        }
    }

    public func shellExportsAfterSnapshot(explicitEnvOverrides: [String: String]) -> String {
        if explicitEnvOverrides["PATH"] != nil { return "" }
        return entries
            .filter { !$0.isEmpty }
            .map { entry in
                let quoted = entry.replacingOccurrences(of: "'", with: "'\\''")
                return "if [ -n \"${PATH:-}\" ]; then export PATH='\(quoted)':\"$PATH\"; else export PATH='\(quoted)'; fi"
            }
            .joined(separator: "\n")
    }
}
