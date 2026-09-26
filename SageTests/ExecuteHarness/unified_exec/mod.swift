//
//  mod.swift
//  SageTests
//
//  Port of selected unified_exec store/env tests (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import CodexProtocol
import CodexShellCommand
@testable import CodexCore
import XCTest

final class UnifiedExecTests: XCTestCase {
    func testApplyUnifiedExecEnvSetsPager() {
        let env = applyUnifiedExecEnv([:])
        XCTAssertEqual(env["PAGER"], "cat")
        XCTAssertEqual(env["NO_COLOR"], "1")
    }

    func testDeterministicProcessIds() {
        setDeterministicProcessIdsForTests(true)
        defer { setDeterministicProcessIdsForTests(false) }
        let manager = UnifiedExecProcessManager()
        XCTAssertEqual(manager.allocateProcessId(), 1)
        XCTAssertEqual(manager.allocateProcessId(), 2)
        manager.releaseProcessId(1)
    }

    func testTerminalReviewRequiresEscalatedOnProfileDrift() {
        var permissions = TerminalPermissions.nativeDefault()
        permissions.launchProfile = .disabled
        switch permissions.reviewRequirement(current: .readOnly(), baseline: .readOnly()) {
        case .success(let value):
            XCTAssertEqual(value, .requireEscalated)
        case .failure(let reason):
            XCTFail(reason.description)
        }
    }

    func testShellSnapshotRequiresLoginFlag() {
        let cwd = PathUri.fromAbsPath(try! AbsolutePathBuf.fromAbsolutePath("/tmp"))
        let request = ExecCommandRequest(
            command: ["/bin/zsh", "-c", "ls"],
            shellType: .zsh,
            hookCommand: "",
            processId: 1,
            yieldTimeMs: 250,
            maxOutputTokens: nil,
            cwd: cwd,
            sandboxCwd: cwd,
            shellMode: .direct,
            network: nil,
            tty: false,
            sandboxPermissions: .useDefault,
            additionalPermissions: nil,
            additionalPermissionsPreapproved: false,
            justification: nil,
            prefixRule: nil
        )
        XCTAssertNil(
            shellSnapshotRequest(
                request: request,
                cwd: cwd,
                snapshotSupported: true,
                featureEnabled: true
            )
        )
    }
}
