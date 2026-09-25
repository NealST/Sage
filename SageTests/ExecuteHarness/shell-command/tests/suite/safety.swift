//
//  safety.swift
//  SageTests
//
//  Port of codex-rs/shell-command dangerous-command tests (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

@testable import CodexShellCommand
import XCTest

final class ShellCommandSafetyTests: XCTestCase {
    func testRmRfIsDangerous() {
        XCTAssertEqual(dangerousCommandMatch(["rm", "-rf", "/"]), .forcedRm)
    }

    func testForcedRmVariants() {
        for command in [
            ["/bin/rm", "-fr", "/tmp/example"],
            ["rm", "-r", "-f", "/tmp/example"],
            ["rm", "--force", "/tmp/example"],
            ["rm", "/tmp/example", "-f"],
            ["sudo", "rm", "-rf", "/tmp/example"],
            ["env", "TARGET=/tmp/example", "rm", "-rf", "/tmp/example"],
        ] {
            XCTAssertEqual(dangerousCommandMatch(command), .forcedRm, "\(command)")
        }
    }

    func testNonForcedRmIsNotDangerous() {
        XCTAssertNil(dangerousCommandMatch(["rm", "-r", "/tmp/example"]))
        XCTAssertNil(dangerousCommandMatch(["rm", "--", "-f"]))
    }

    func testDetectShellType() {
        XCTAssertEqual(detectShellType("/bin/zsh"), .zsh)
        XCTAssertEqual(detectShellType("bash"), .bash)
        XCTAssertEqual(detectShellType("pwsh"), .powerShell)
    }

    func testParseSimpleCommand() {
        let parsed = parseCommand(["ls", "-1", "/tmp"])
        guard case .listFiles(let cmd, let path) = parsed.first else {
            return XCTFail("expected listFiles")
        }
        XCTAssertTrue(cmd.contains("ls"))
        XCTAssertEqual(path, "/tmp")
    }

    func testShellStartupScript() {
        XCTAssertTrue(shellStartupScript(.zsh).contains(".zshrc"))
        XCTAssertTrue(shellStartupScript(.bash).contains(".bashrc"))
        XCTAssertEqual(shellStartupScript(.sh), "")
    }
}
