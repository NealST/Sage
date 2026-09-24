//
//  path_utils_tests.swift
//  SageTests
//
//  Port of codex-rs/utils/path-utils/src/path_utils_tests.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  Not ported (plan §2.3): the `wsl` module (`cfg(target_os = "linux")`) and
//  the `cfg(windows)` tests (`windows_verbatim_paths_are_simplified`,
//  `matches_windows_verbatim_paths`).
//
//  `tempfile::tempdir` maps to a unique directory under
//  NSTemporaryDirectory; `std::os::unix::fs::symlink` maps to
//  `FileManager.createSymbolicLink`.
//

import Foundation
import XCTest
@testable import CodexUtils

final class PathUtilsTests: XCTestCase {

    /// `tempfile::tempdir`.
    private func tempdir() throws -> String {
        let dir = NSTemporaryDirectory() + "path-utils-tests-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    /// `replace_path_and_deduplicate_preserves_other_paths_and_order`.
    func testReplacePathAndDeduplicatePreservesOtherPathsAndOrder() {
        let oldPath = "old"
        let newPath = "new"
        let extra = "extra"
        let descendant = "old/child"

        XCTAssertEqual(
            replacePathAndDeduplicate(
                [oldPath, extra, descendant, newPath, extra],
                oldPath: oldPath,
                newPath: newPath
            ),
            [newPath, extra, descendant]
        )
    }

    /// `symlinks::symlink_cycles_fall_back_to_root_write_path`.
    func testSymlinkCyclesFallBackToRootWritePath() throws {
        let dir = try tempdir()
        let a = dir + "/a"
        let b = dir + "/b"

        try FileManager.default.createSymbolicLink(atPath: a, withDestinationPath: b)
        try FileManager.default.createSymbolicLink(atPath: b, withDestinationPath: a)

        let resolved = try resolveSymlinkWritePaths(a)

        XCTAssertNil(resolved.readPath)
        XCTAssertEqual(resolved.writePath, a)
    }

    /// `native_workdir::non_windows_paths_are_unchanged`.
    func testNonWindowsPathsAreUnchanged() {
        let path = #"\\?\D:\c\x\worktrees\2508\swift-base"#
        let normalized = normalizeForNativeWorkdirWithFlag(path, isWindows: false)

        XCTAssertEqual(normalized, path)
    }

    /// `path_comparison::matches_identical_existing_paths`.
    func testMatchesIdenticalExistingPaths() throws {
        let dir = try tempdir()

        XCTAssertTrue(pathsMatchAfterNormalization(dir, dir))
    }

    /// `path_comparison::falls_back_to_raw_equality_when_paths_cannot_be_normalized`.
    func testFallsBackToRawEqualityWhenPathsCannotBeNormalized() {
        XCTAssertTrue(pathsMatchAfterNormalization("missing", "missing"))
        XCTAssertFalse(pathsMatchAfterNormalization("missing-a", "missing-b"))
    }
}
