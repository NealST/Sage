//
//  shell.swift
//  SageTests
//
//  Port of codex-rs/core/src/shell.rs tests (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import CodexShellCommand
@testable import CodexCore
import XCTest

final class ShellTests: XCTestCase {
    func testDeriveLoginAndNonLoginArgs() {
        let shell = Shell(shellType: .zsh, shellPath: "/bin/zsh")
        XCTAssertEqual(shell.deriveExecArgs("ls", useLoginShell: true), ["/bin/zsh", "-lc", "ls"])
        XCTAssertEqual(shell.deriveExecArgs("ls", useLoginShell: false), ["/bin/zsh", "-c", "ls"])
    }

    func testDefaultUserShellIsPosix() {
        let shell = defaultUserShell()
        XCTAssertTrue([ShellType.zsh, .bash, .sh].contains(shell.shellType))
        XCTAssertFalse(shell.shellPath.isEmpty)
    }

    func testModelProvidedPathSelectsType() {
        let shell = getShellByModelProvidedPath("/usr/bin/bash")
        XCTAssertEqual(shell.shellType, .bash)
    }
}
