//
//  command_canonicalization.swift
//  SageTests
//
//  Port of codex-rs/core/src/command_canonicalization.rs tests (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//

@testable import Sage
import XCTest

final class CommandCanonicalizationTests: XCTestCase {
    func testUnwrapsSinglePlainCommand() {
        XCTAssertEqual(
            canonicalizeCommandForApproval(["/bin/bash", "-lc", "ls -la"]),
            ["ls", "-la"]
        )
    }

    func testPreservesComplexScriptText() {
        XCTAssertEqual(
            canonicalizeCommandForApproval(["bash", "-lc", "echo hi && echo bye"]),
            [CANONICAL_BASH_SCRIPT_PREFIX, "-lc", "echo hi && echo bye"]
        )
    }

    func testLeavesUnparsedArgvUnchanged() {
        XCTAssertEqual(
            canonicalizeCommandForApproval(["git", "status"]),
            ["git", "status"]
        )
    }
}
