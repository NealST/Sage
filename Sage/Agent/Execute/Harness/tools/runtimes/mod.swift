//
//  mod.swift
//  ToolsRuntimes
//
//  Port of codex-rs/core/src/tools/runtimes/mod.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  PATH prepend and managed-proxy env cleanup are Session-free.
//  Managed CA bundle hashing stays out.
//

import SageProtocol
import Foundation

public let SNAPSHOT_ORIGINAL_BASH_ENV_ENV_KEY = "SAGE_NETWORK_PROXY_SNAPSHOT_ORIGINAL_BASH_ENV"
public let SNAPSHOT_ORIGINAL_POSIX_ENV_ENV_KEY = "SAGE_NETWORK_PROXY_SNAPSHOT_ORIGINAL_POSIX_ENV"
public let SNAPSHOT_ORIGINAL_ZDOTDIR_ENV_KEY = "SAGE_NETWORK_PROXY_SNAPSHOT_ORIGINAL_ZDOTDIR"
public let SNAPSHOT_BROKERED_VALUE_ENV_PREFIX = "SAGE_NETWORK_PROXY_SNAPSHOT_BROKERED_VALUE_"
public let SNAPSHOT_BROKERED_UNSET_ENV_PREFIX = "SAGE_NETWORK_PROXY_SNAPSHOT_BROKERED_UNSET_"
public let PROXY_ACTIVE_ENV_KEY = "SAGE_NETWORK_PROXY_ACTIVE"

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

public let sageProxyGitSshCommandMarker = "SAGE_PROXY_GIT_SSH_COMMAND=1 "

public let managedProxyEnvKeys: Set<String> = [
    PROXY_ACTIVE_ENV_KEY,
    "HTTP_PROXY",
    "HTTPS_PROXY",
    "http_proxy",
    "https_proxy",
    "YARN_HTTP_PROXY",
    "YARN_HTTPS_PROXY",
    "npm_config_http_proxy",
    "npm_config_https_proxy",
    "npm_config_proxy",
    "NPM_CONFIG_HTTP_PROXY",
    "NPM_CONFIG_HTTPS_PROXY",
    "NPM_CONFIG_PROXY",
    "BUNDLE_HTTP_PROXY",
    "BUNDLE_HTTPS_PROXY",
    "PIP_PROXY",
    "DOCKER_HTTP_PROXY",
    "DOCKER_HTTPS_PROXY",
    "WS_PROXY",
    "WSS_PROXY",
    "ws_proxy",
    "wss_proxy",
    "NO_PROXY",
    "no_proxy",
    "npm_config_noproxy",
    "NPM_CONFIG_NOPROXY",
    "YARN_NO_PROXY",
    "BUNDLE_NO_PROXY",
    "ALL_PROXY",
    "all_proxy",
    "FTP_PROXY",
    "ftp_proxy",
]

public func stripManagedProxyEnv(_ env: [String: String]) -> [String: String] {
    let brokeredKeys = brokeredCredentialKeys(env)
    return env.filter { key, value in
        !brokeredKeys.contains(key) && !isManagedProxyEnvVar(key, value: value)
    }
}

public func isManagedProxyEnvVar(_ key: String, value: String) -> Bool {
    if key.hasPrefix("SAGE_NETWORK_PROXY_") || managedProxyEnvKeys.contains(key) {
        return true
    }
    return key == "GIT_SSH_COMMAND" && value.hasPrefix(sageProxyGitSshCommandMarker)
}

private func brokeredCredentialKeys(_ env: [String: String]) -> Set<String> {
    guard let raw = env["SAGE_NETWORK_PROXY_BROKERED_CREDENTIALS"],
          let data = raw.data(using: .utf8),
          let pairs = try? JSONSerialization.jsonObject(with: data) as? [Any]
    else { return [] }
    var keys = Set<String>()
    for pair in pairs {
        guard let values = pair as? [String], values.count == 2, env[values[0]] == values[1] else {
            continue
        }
        keys.insert(values[0])
    }
    return keys
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
