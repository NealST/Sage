//
//  info.swift
//  SageTests
//
//  Port of codex-rs/git-utils/src/info.rs get_git_repo_root tests (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Exercises `getGitRepoRoot` on a temporary git repository.
//

import CodexGitUtils
import Foundation
import XCTest

final class GitUtilsInfoTests: XCTestCase {
    private var tempRoot: String?

    override func tearDown() {
        if let tempRoot {
            try? FileManager.default.removeItem(atPath: tempRoot)
        }
        super.tearDown()
    }

    func testGetGitRepoRootFindsTempRepository() throws {
        let root = NSTemporaryDirectory() + "git-info-" + UUID().uuidString
        tempRoot = root
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-c", SAFE_BARE_REPOSITORY_CONFIG, "init", "-q"]
        process.currentDirectoryURL = URL(fileURLWithPath: root)
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)

        let nested = (root as NSString).appendingPathComponent("src/nested")
        try FileManager.default.createDirectory(atPath: nested, withIntermediateDirectories: true)

        let fromNested = getGitRepoRoot(nested)
        let fromRoot = getGitRepoRoot(root)
        XCTAssertEqual(fromRoot.map { ($0 as NSString).standardizingPath }, (root as NSString).standardizingPath)
        XCTAssertEqual(fromNested.map { ($0 as NSString).standardizingPath }, (root as NSString).standardizingPath)
    }

    func testGetGitRepoRootReturnsNilOutsideARepo() throws {
        let root = NSTemporaryDirectory() + "git-info-empty-" + UUID().uuidString
        tempRoot = root
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        XCTAssertNil(getGitRepoRoot(root))
    }
}
