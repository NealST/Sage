//
//  exec_env.swift
//  SageTests
//
//  Port of codex-rs/core/src/exec_env.rs tests (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import ApplyPatch
import CodexProtocol
@testable import CodexCore
import XCTest

final class ExecEnvTests: XCTestCase {
    func testInjectsPermissionProfile() {
        var env = ["PATH": "/bin"]
        injectPermissionProfileEnv(
            &env,
            activePermissionProfile: ActivePermissionProfile(id: ":workspace")
        )
        XCTAssertEqual(env[CODEX_PERMISSION_PROFILE_ENV_VAR], ":workspace")
    }

    func testClearsPermissionProfileWhenNil() {
        var env = [CODEX_PERMISSION_PROFILE_ENV_VAR: "stale"]
        injectPermissionProfileEnv(&env, activePermissionProfile: nil)
        XCTAssertNil(env[CODEX_PERMISSION_PROFILE_ENV_VAR])
    }

    func testInjectApplyPatchEnvHonorsFeatureBit() {
        var env = [CODEX_APPLY_PATCH_PRESERVE_LINE_ENDINGS_ENV_VAR.lowercased(): "stale"]
        injectApplyPatchEnv(&env, preserveLineEndings: true)
        XCTAssertNil(env[CODEX_APPLY_PATCH_PRESERVE_LINE_ENDINGS_ENV_VAR.lowercased()])
        XCTAssertEqual(env[CODEX_APPLY_PATCH_PRESERVE_LINE_ENDINGS_ENV_VAR], "1")
    }
}
