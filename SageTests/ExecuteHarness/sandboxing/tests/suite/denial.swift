//
//  denial.swift
//  SageTests
//
//  Port of codex-rs/sandboxing denial + violation tests (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import CodexProtocol
@testable import CodexSandboxing
import XCTest

final class SandboxingDenialTests: XCTestCase {
    func testLegacyDenialKeywords() {
        for keyword in [
            "operation not permitted",
            "permission denied",
            "read-only file system",
            "seccomp",
            "sandbox",
            "landlock",
            "failed to write file",
        ] {
            let output = makeExecOutput(exitCode: 1, stderr: keyword)
            XCTAssertNotNil(
                classifyFilesystemSandboxViolation(sandboxType: .linuxSeccomp, execOutput: output),
                keyword
            )
        }
    }

    func testPreservesLegacyDenialOrdering() {
        let quickRejectWithoutKeyword = makeExecOutput(exitCode: 127, stderr: "command not found")
        let quickRejectWithKeyword = makeExecOutput(exitCode: 127, stderr: "Permission denied")
        let zeroExit = makeExecOutput(exitCode: 0, stderr: "Operation not permitted")
        let noneSandbox = makeExecOutput(exitCode: 1, stderr: "Operation not permitted")

        XCTAssertNil(classifyFilesystemSandboxViolation(sandboxType: .linuxSeccomp, execOutput: quickRejectWithoutKeyword))
        XCTAssertNotNil(classifyFilesystemSandboxViolation(sandboxType: .linuxSeccomp, execOutput: quickRejectWithKeyword))
        XCTAssertNil(classifyFilesystemSandboxViolation(sandboxType: .linuxSeccomp, execOutput: zeroExit))
        XCTAssertNil(classifyFilesystemSandboxViolation(sandboxType: .none, execOutput: noneSandbox))
    }

    func testClassifiesFilesystemViolationWithPath() {
        let output = makeExecOutput(
            exitCode: 1,
            stderr: "bash: /private/tmp/denied: Operation not permitted"
        )
        XCTAssertEqual(
            classifyFilesystemSandboxViolation(sandboxType: .macosSeatbelt, execOutput: output),
            FileSystemSandboxViolation(
                backend: .seatbelt,
                reason: .operationNotPermitted,
                path: "/private/tmp/denied",
                outputSnippet: "bash: /private/tmp/denied: Operation not permitted"
            )
        )
    }

    func testPlatformSandboxIsSeatbelt() {
        XCTAssertEqual(getPlatformSandbox(windowsSandboxEnabled: false), .macosSeatbelt)
    }

    func testSeatbeltCommandArgsIncludeBasePolicyAndCommand() throws {
        let cwd = FileManager.default.currentDirectoryPath
        let args = try createSeatbeltCommandArgs(
            CreateSeatbeltCommandArgsParams(
                command: ["echo", "hi"],
                fileSystemSandboxPolicy: FileSystemSandboxPolicy(
                    kind: .unrestricted,
                    entries: []
                ),
                networkSandboxPolicy: .enabled,
                sandboxPolicyCwd: cwd,
                enforceManagedNetwork: false
            )
        )
        XCTAssertEqual(args.first, "-p")
        XCTAssertTrue(args.contains("--"))
        XCTAssertEqual(args.last, "hi")
        XCTAssertTrue(args[1].contains("(deny default)"))
    }
}

private func makeExecOutput(
    exitCode: Int32,
    stdout: String = "",
    stderr: String = "",
    aggregated: String = ""
) -> ExecToolCallOutput {
    ExecToolCallOutput(
        exitCode: exitCode,
        stdout: .new(stdout),
        stderr: .new(stderr),
        aggregatedOutput: .new(aggregated.isEmpty ? stderr : aggregated),
        duration: .milliseconds(1),
        timedOut: false
    )
}
