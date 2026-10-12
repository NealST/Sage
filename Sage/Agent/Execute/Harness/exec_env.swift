//
//  exec_env.swift
//  Sage
//
//  Port of codex-rs/core/src/exec_env.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Environment construction delegates to `SageProtocol.createEnv`.
//  `codex_features::Features` is not ported yet, so apply-patch line-ending
//  injection takes the feature bit as a Bool. `CARGO_PKG_VERSION` is the
//  Sage bundle version.
//

import ApplyPatch
import SageProtocol
import Foundation

public let SAGE_VERSION_ENV_VAR = "SAGE_VERSION"
public let SAGE_PERMISSION_PROFILE_ENV_VAR = "SAGE_PERMISSION_PROFILE"

public func createEnv(
    policy: ShellEnvironmentPolicy,
    threadId: ThreadId?
) -> [String: String] {
    SageProtocol.createEnv(policy: policy, threadId: threadId.map(\.description))
}

func injectSessionEnv(_ env: inout [String: String], sessionId: SessionId) {
    env[sageSessionIdEnvVar] = sessionId.description
    env[SAGE_VERSION_ENV_VAR] = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        ?? "0.0.0"
}

func injectPermissionProfileEnv(
    _ env: inout [String: String],
    activePermissionProfile: ActivePermissionProfile?
) {
    env.removeValue(forKey: SAGE_PERMISSION_PROFILE_ENV_VAR)
    if let activePermissionProfile {
        env[SAGE_PERMISSION_PROFILE_ENV_VAR] = activePermissionProfile.id
    }
}

public func injectApplyPatchEnv(_ env: inout [String: String], preserveLineEndings: Bool) {
    let matches = env.keys.filter { $0.caseInsensitiveCompare(SAGE_APPLY_PATCH_PRESERVE_LINE_ENDINGS_ENV_VAR) == .orderedSame }
    for key in matches {
        env.removeValue(forKey: key)
    }
    if preserveLineEndings {
        env[SAGE_APPLY_PATCH_PRESERVE_LINE_ENDINGS_ENV_VAR] = "1"
    }
}
