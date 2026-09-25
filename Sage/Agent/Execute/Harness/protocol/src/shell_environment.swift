//
//  shell_environment.swift
//  CodexProtocol
//
//  Port of codex-rs/protocol/src/shell_environment.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Shell environment construction from policy. Upstream scrubs non-inheritable
//  env vars from `std::process::Command`; Sage does not spawn child processes
//  directly from the harness, so `scrubNonInheritableEnvVars` operates on a
//  dictionary instead. Windows-only code paths are omitted (platform: macOS).
//

import Foundation

// MARK: - Constants

public let codexSessionIdEnvVar = "CODEX_SESSION_ID"
public let codexThreadIdEnvVar = "CODEX_THREAD_ID"
public let codexExecServerNoiseAuthTokenEnvVar = "CODEX_EXEC_SERVER_NOISE_AUTH_TOKEN"
public let openaiFederationRuleIdEnvVar = "OPENAI_FEDERATION_RULE_ID"
public let openaiIdentityTokenFileEnvVar = "OPENAI_IDENTITY_TOKEN_FILE"
public let openaiWorkloadIdentityContextEnvVar = "OPENAI_WORKLOAD_IDENTITY_CONTEXT"

/// Environment variables that model-reachable child processes must not inherit.
public let nonInheritableEnvVars: [String] = [
    codexExecServerNoiseAuthTokenEnvVar,
    "NODE_REPL_AUTH_TOKEN",
    openaiFederationRuleIdEnvVar,
    openaiIdentityTokenFileEnvVar,
    openaiWorkloadIdentityContextEnvVar,
]

public func isNonInheritableEnvVar(_ name: String) -> Bool {
    nonInheritableEnvVars.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame })
}

/// Removes non-inheritable variables from a mutable environment dictionary.
public func scrubNonInheritableEnvVars(_ env: inout [String: String]) {
    env = env.filter { !isNonInheritableEnvVar($0.key) }
}

// MARK: - Core env var lists

private let unixCoreEnvVars: [String] = [
    "PATH", "SHELL", "TMPDIR", "TEMP", "TMP", "HOME", "LANG", "LC_ALL", "LC_CTYPE", "LOGNAME",
    "USER",
]

// MARK: - createEnv

/// Construct a shell environment from the current process environment and
/// shell-environment policy.
public func createEnv(
    policy: ShellEnvironmentPolicy,
    threadId: String? = nil
) -> [String: String] {
    let vars = ProcessInfo.processInfo.environment.map { ($0.key, $0.value) }
    return createEnvFromVars(vars, policy: policy, threadId: threadId)
}

/// Construct a shell environment from the supplied variable list and policy.
public func createEnvFromVars(
    _ vars: [(String, String)],
    policy: ShellEnvironmentPolicy,
    threadId: String? = nil
) -> [String: String] {
    populateEnv(vars, policy: policy, threadId: threadId)
}

/// Core environment population logic matching upstream `populate_env`.
public func populateEnv(
    _ vars: [(String, String)],
    policy: ShellEnvironmentPolicy,
    threadId: String? = nil
) -> [String: String] {
    // Step 1 — determine the starting set.
    var envMap: [String: String]
    switch policy.inherit {
    case .all:
        envMap = Dictionary(vars, uniquingKeysWith: { _, last in last })
    case .none:
        envMap = [:]
    case .core:
        envMap = Dictionary(
            vars.filter { pair in
                unixCoreEnvVars.contains(where: {
                    $0.caseInsensitiveCompare(pair.0) == .orderedSame
                })
            },
            uniquingKeysWith: { _, last in last }
        )
    }

    // Step 2 — apply default excludes unless disabled.
    if !policy.ignoreDefaultExcludes {
        let defaultExcludes = [
            EnvironmentVariablePattern.newCaseInsensitive("*KEY*"),
            EnvironmentVariablePattern.newCaseInsensitive("*SECRET*"),
            EnvironmentVariablePattern.newCaseInsensitive("*TOKEN*"),
        ]
        envMap = envMap.filter { pair in
            !defaultExcludes.contains(where: { $0.matches(pair.key) })
        }
    }

    // Step 3 — custom excludes.
    if !policy.exclude.isEmpty {
        envMap = envMap.filter { pair in
            !policy.exclude.contains(where: { $0.matches(pair.key) })
        }
    }

    // Step 4 — user-provided overrides.
    for (key, val) in policy.set {
        envMap[key] = val
    }

    // Step 5 — include-only filter.
    if !policy.includeOnly.isEmpty {
        envMap = envMap.filter { pair in
            policy.includeOnly.contains(where: { $0.matches(pair.key) })
        }
    }

    // Step 6 — thread ID.
    if let threadId {
        envMap[codexThreadIdEnvVar] = threadId
    }

    // Non-inheritable launch context cannot be restored through overrides.
    envMap = envMap.filter { !isNonInheritableEnvVar($0.key) }

    return envMap
}
