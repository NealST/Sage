//
//  parse_command.swift
//  SageTests
//
//  Port of focused cases from
//  codex-rs/shell-command/src/parse_command.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

@testable import CodexShellCommand
import CodexProtocol
import XCTest

final class ParseCommandTests: XCTestCase {
    func testGitStatusIsUnknown() {
        XCTAssertEqual(parseCommand(["git", "status"]), [.unknown(cmd: "git status")])
    }

    func testGitGrepAndLsFiles() {
        XCTAssertEqual(
            parseCommand(["git", "grep", "TODO", "src"]),
            [.search(cmd: "git grep TODO src", query: "TODO", path: "src")])
        XCTAssertEqual(
            parseCommand(["git", "ls-files"]),
            [.listFiles(cmd: "git ls-files", path: nil)])
        XCTAssertEqual(
            parseCommand(["git", "ls-files", "src"]),
            [.listFiles(cmd: "git ls-files src", path: "src")])
    }

    func testCatAndHeadAreReads() {
        XCTAssertEqual(
            parseCommand(["cat", "README.md"]),
            [.read(cmd: "cat README.md", name: "README.md", path: "README.md")])
        XCTAssertEqual(
            parseCommand(["head", "-n", "40", "foo/bar.txt"]),
            [.read(cmd: "head -n 40 foo/bar.txt", name: "bar.txt", path: "foo/bar.txt")])
    }

    func testRgSearchAndFiles() {
        XCTAssertEqual(
            parseCommand(["rg", "TODO", "src"]),
            [.search(cmd: "rg TODO src", query: "TODO", path: "src")])
        XCTAssertEqual(
            parseCommand(["rg", "--files", "src"]),
            [.listFiles(cmd: "rg --files src", path: "src")])
    }

    func testFindNameIsSearch() {
        XCTAssertEqual(
            parseCommand(["find", ".", "-name", "*.swift"]),
            [.search(cmd: "find . -name '*.swift'", query: "*.swift", path: ".")])
    }

    func testCdThenCatJoinsPath() {
        XCTAssertEqual(
            parseCommand(["cd", "src", "&&", "cat", "main.swift"]),
            [.read(cmd: "cat main.swift", name: "main.swift", path: "src/main.swift")])
    }

    func testIsPathish() {
        XCTAssertTrue(isPathish("./foo"))
        XCTAssertTrue(isPathish("foo/bar"))
        XCTAssertFalse(isPathish("TODO"))
    }
}
