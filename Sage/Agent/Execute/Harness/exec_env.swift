//
//  exec_env.swift
//  Sage
//
//  Port of codex-rs/core/src/exec_env.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Environment construction delegates to `CodexProtocol.createEnv`.
//  `codex_features::Features` is not ported yet, so apply-patch line-ending
//  injection takes the feature bit as a Bool. `CARGO_PKG_VERSION` is the
//  Sage bundle version.
//

import ApplyPatch
import CodexProtocol
import Foundation

public let CODEX_VERSION_ENV_VAR = "CODEX_VERSION"
public let CODEX_PERMISSION_PROFILE_ENV_VAR = "CODEX_PERMISSION_PROFILE"

public func createEnv(
    policy: ShellEnvironmentPolicy,
    threadId: ThreadId?
) -> [String: String] {
    CodexProtocol.createEnv(policy: policy, threadId: threadId.map(\.description))
}

func injectSessionEnv(_ env: inout [String: String], sessionId: SessionId) {
    env[codexSessionIdEnvVar] = sessionId.description
    env[CODEX_VERSION_ENV_VAR] = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        ?? "0.0.0"
}

func injectPermissionProfileEnv(
    _ env: inout [String: String],
    activePermissionProfile: ActivePermissionProfile?
) {
    env.removeValue(forKey: CODEX_PERMISSION_PROFILE_ENV_VAR)
    if let activePermissionProfile {
        env[CODEX_PERMISSION_PROFILE_ENV_VAR] = activePermissionProfile.id
    }
}

public func injectApplyPatchEnv(_ env: inout [String: String], preserveLineEndings: Bool) {
    let matches = env.keys.filter { $0.caseInsensitiveCompare(CODEX_APPLY_PATCH_PRESERVE_LINE_ENDINGS_ENV_VAR) == .orderedSame }
    for key in matches {
        env.removeValue(forKey: key)
    }
    if preserveLineEndings {
        env[CODEX_APPLY_PATCH_PRESERVE_LINE_ENDINGS_ENV_VAR] = "1"
    }
}
