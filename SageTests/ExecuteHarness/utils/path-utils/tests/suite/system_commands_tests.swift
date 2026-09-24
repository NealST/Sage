//
//  system_commands_tests.swift
//  SageTests
//
//  Port of codex-rs/utils/path-utils/src/system_commands_tests.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  Unix-only test upstream; `dunce::canonicalize` maps to `realpathString`,
//  `std::env::consts::EXE_SUFFIX` is "" on macOS.
//

import Foundation
import XCTest
@testable import CodexUtils

final class SystemCommandsTests: XCTestCase {

    /// `resolves_only_executables_inside_installation_directories`.
    func testResolvesOnlyExecutablesInsideInstallationDirectories() throws {
        let root = NSTemporaryDirectory() + "system-commands-tests-" + UUID().uuidString
        let bin = root + "/bin"
        try FileManager.default.createDirectory(atPath: bin, withIntermediateDirectories: true)
        let executable = bin + "/helper"
        try "installed helper".write(toFile: executable, atomically: false, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable
        )
        let directories = [try realpathString(bin)]
        // The shim's `XCTAssertEqual` is `rethrows`: a throwing argument
        // makes the whole call throwing.
        try XCTAssertEqual(
            executableInDirectories("helper", directories),
            try realpathString(executable)
        )
        XCTAssertNil(executableInDirectories("../helper", directories))
        XCTAssertNil(executableInDirectories("missing", directories))

        // A symlink escaping the installation directories is not installed.
        let outside = root + "/outside"
        try FileManager.default.moveItem(atPath: executable, toPath: outside)
        try FileManager.default.createSymbolicLink(atPath: executable, withDestinationPath: outside)
        XCTAssertNil(executableInDirectories("helper", directories))
    }
}
