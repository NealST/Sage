//
//  pty.swift
//  SageTests
//
//  Port of selected utils/pty spawn coverage (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import CodexUtils
import XCTest

final class PtySpawnTests: XCTestCase {
    func testPipeProcessEcho() async throws {
        let spawned = try await spawnPipeProcess(
            program: "/bin/echo",
            args: ["pty-ok"],
            cwd: FileManager.default.currentDirectoryPath,
            env: ProcessInfo.processInfo.environment
        )
        var collected = Data()
        for await chunk in spawned.stdout {
            collected.append(chunk)
        }
        let code = await spawned.exit.value
        XCTAssertEqual(code, 0)
        XCTAssertTrue(String(decoding: collected, as: UTF8.self).contains("pty-ok"))
    }

    func testCommandBuilderRejectsNul() {
        let command = Command("/bin/echo")
        command.arg("ok\0bad")
        XCTAssertThrowsError(try command.spawn())
    }
}
