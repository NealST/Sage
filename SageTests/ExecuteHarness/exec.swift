//
//  exec.swift
//  SageTests
//
//  Port of selected codex-rs/core/src/exec_tests.rs cases (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import CodexProtocol
import CodexUtils
@testable import CodexCore
import XCTest

final class ExecTests: XCTestCase {
    func testEchoCapturesStdout() async throws {
        let cwd = try AbsolutePathBuf.currentDir()
        let result = await processExecToolCall(
            ExecParams(
                command: ["/bin/echo", "hello-sage"],
                cwd: cwd,
                expiration: .timeout(.seconds(5)),
                capturePolicy: .shellTool,
                env: ProcessInfo.processInfo.environment
            ),
            permissionProfile: .disabled,
            sandboxCwd: cwd
        )
        let output = try result.get()
        XCTAssertEqual(output.exitCode, 0)
        XCTAssertTrue(output.stdout.text.contains("hello-sage"))
        XCTAssertFalse(output.timedOut)
    }

    func testEmptyCommandIsIoError() async {
        let cwd = try? AbsolutePathBuf.currentDir()
        guard let cwd else { return }
        let result = await processExecToolCall(
            ExecParams(
                command: [],
                cwd: cwd,
                expiration: .timeout(.seconds(1))
            ),
            permissionProfile: .disabled,
            sandboxCwd: cwd
        )
        guard case .failure(let error) = result else {
            XCTFail("expected failure")
            return
        }
        XCTAssertEqual(error.details, .io("command args are empty"))
    }

    func testTimeoutKillsSleep() async throws {
        let cwd = try AbsolutePathBuf.currentDir()
        let result = await processExecToolCall(
            ExecParams(
                command: ["/bin/sleep", "20"],
                cwd: cwd,
                expiration: .timeout(.milliseconds(200)),
                env: ProcessInfo.processInfo.environment
            ),
            permissionProfile: .disabled,
            sandboxCwd: cwd
        )
        guard case .failure(let error) = result else {
            XCTFail("expected timeout")
            return
        }
        guard case .sandbox(.timeout) = error.details else {
            XCTFail("expected sandbox timeout, got \(error.details)")
            return
        }
    }

    func testClampYieldTime() {
        XCTAssertEqual(clampYieldTime(0), MIN_YIELD_TIME_MS)
        XCTAssertEqual(clampYieldTime(1_000), 1_000)
        XCTAssertEqual(clampYieldTime(99_000), MAX_YIELD_TIME_MS)
    }
}
