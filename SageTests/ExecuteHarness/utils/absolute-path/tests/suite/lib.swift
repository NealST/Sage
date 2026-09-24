//
//  lib.swift
//  SageTests
//
//  Port of codex-rs/utils/absolute-path/src/lib.rs #[cfg(test)] (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  Unix tests only. Not ported:
//  - `from_absolute_path_with_removed_current_dir` (spawns the test binary by
//    name with a removed cwd — no XCTest equivalent)
//  - `#[cfg(windows)]` tests (plan §2.3)
//

import Foundation
import XCTest
@testable import CodexUtils

final class AbsolutePathBufTests: XCTestCase {
    /// `tempfile::tempdir`.
    private func tempdir() throws -> String {
        let dir = NSTemporaryDirectory() + "absolute-path-tests-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    override func tearDown() throws {
        try super.tearDown()
    }

    func testCreateWithAbsolutePathIgnoresBasePath() throws {
        let baseDir = try tempdir()
        let absoluteDir = try tempdir()
        let absolutePath = absoluteDir + "/file.txt"
        let absPathBuf = AbsolutePathBuf.resolvePathAgainstBase(absolutePath, basePath: baseDir)
        XCTAssertEqual(absPathBuf.asPath, absolutePath)
    }

    func testFromAbsolutePathCheckedRejectsRelativePath() {
        XCTAssertThrowsError(try AbsolutePathBuf.fromAbsolutePathChecked("relative/path")) { error in
            XCTAssertEqual((error as? IOError)?.kind, .invalidInput)
        }
    }

    func testNormalizeWindowsDevicePathStripsSupportedVerbatimPrefixes() {
        XCTAssertEqual(
            normalizeWindowsDevicePath(#"\\?\D:\c\x\worktrees\2508\swift-base"#),
            #"D:\c\x\worktrees\2508\swift-base"#
        )
        XCTAssertEqual(
            normalizeWindowsDevicePath(#"\\.\D:\c\x\worktrees\2508\swift-base"#),
            #"D:\c\x\worktrees\2508\swift-base"#
        )
        XCTAssertEqual(
            normalizeWindowsDevicePath(#"\\?\UNC\server\share\workspace"#),
            #"\\server\share\workspace"#
        )
        XCTAssertEqual(
            normalizeWindowsDevicePath(#"\\.\UNC\server\share\workspace"#),
            #"\\server\share\workspace"#
        )
        XCTAssertNil(normalizeWindowsDevicePath(#"\\?\GLOBALROOT\Device"#))
    }

    func testRelativePathIsResolvedAgainstBasePath() throws {
        let baseDir = try tempdir()
        let absPathBuf = AbsolutePathBuf.resolvePathAgainstBase("file.txt", basePath: baseDir)
        XCTAssertEqual(absPathBuf.asPath, baseDir + "/file.txt")
    }

    func testRelativePathDotsAreNormalizedAgainstBasePath() throws {
        let baseDir = try tempdir()
        let absPathBuf = AbsolutePathBuf.resolvePathAgainstBase("./nested/../file.txt", basePath: baseDir)
        XCTAssertEqual(absPathBuf.asPath, baseDir + "/file.txt")
    }

    func testCanonicalizeReturnsAbsolutePathBuf() throws {
        let baseDir = try tempdir()
        try FileManager.default.createDirectory(atPath: baseDir + "/one", withIntermediateDirectories: false)
        try FileManager.default.createDirectory(atPath: baseDir + "/two", withIntermediateDirectories: false)
        try "".write(toFile: baseDir + "/two/file.txt", atomically: false, encoding: .utf8)
        let absPathBuf = try AbsolutePathBuf.fromAbsolutePath(baseDir + "/one/../two/./file.txt")
        try XCTAssertEqual(
            absPathBuf.canonicalize().asPath,
            realpathString(baseDir + "/two/file.txt")
        )
    }

    func testCanonicalizeReturnsErrorForMissingPath() throws {
        let baseDir = try tempdir()
        let absPathBuf = try AbsolutePathBuf.fromAbsolutePath(baseDir + "/missing.txt")
        XCTAssertThrowsError(try absPathBuf.canonicalize())
    }

    func testAncestorsReturnsAbsolutePathBufs() throws {
        let absPathBuf = try AbsolutePathBuf.fromAbsolutePathChecked(
            AbsolutePathTestSupport.testPathBuf("/tmp/one/two")
        )
        let ancestors = absPathBuf.ancestors().map(\.path)
        XCTAssertEqual(ancestors, ["/tmp/one/two", "/tmp/one", "/tmp", "/"])
    }

    func testRelativeToCurrentDirResolvesRelativePath() throws {
        let currentDir = FileManager.default.currentDirectoryPath
        let absPathBuf = try AbsolutePathBuf.relativeToCurrentDir("file.txt")
        XCTAssertEqual(absPathBuf.asPath, currentDir + "/file.txt")
    }

    func testGuardUsedInDeserialization() throws {
        let baseDir = try tempdir()
        let relativePath = "subdir/file.txt"
        let guard_ = AbsolutePathBufGuard(basePath: baseDir)
        let absPathBuf = try JSONDecoder().decode(
            AbsolutePathBuf.self,
            from: Data("\"\(relativePath)\"".utf8)
        )
        _ = guard_ // keep the guard alive until decoding finished
        XCTAssertEqual(absPathBuf.asPath, baseDir + "/" + relativePath)
    }

    func testHomeDirectoryRootIsExpandedInDeserialization() throws {
        guard let home = AbsolutePathBufGuard.homeDirectory() else { return }
        let baseDir = try tempdir()
        let guard_ = AbsolutePathBufGuard(basePath: baseDir)
        let absPathBuf = try JSONDecoder().decode(AbsolutePathBuf.self, from: Data("\"~\"".utf8))
        _ = guard_
        XCTAssertEqual(absPathBuf.asPath, home)
    }

    func testHomeDirectorySubpathIsExpandedInDeserialization() throws {
        guard let home = AbsolutePathBufGuard.homeDirectory() else { return }
        let baseDir = try tempdir()
        let guard_ = AbsolutePathBufGuard(basePath: baseDir)
        let absPathBuf = try JSONDecoder().decode(AbsolutePathBuf.self, from: Data("\"~/code\"".utf8))
        _ = guard_
        XCTAssertEqual(absPathBuf.asPath, home + "/code")
    }

    func testExplicitHomeDirectoryIsUsedWithExistingPathGuards() throws {
        let homeDir = try tempdir()
        let baseDir = try tempdir()

        let (homePath, relativePath) = try AbsolutePathBufGuard.withHomeDirectory(homeDir) {
            let guard_ = AbsolutePathBufGuard(basePath: baseDir)
            let homePath = try JSONDecoder().decode(AbsolutePathBuf.self, from: Data("\"~/code\"".utf8))
            let relativePath = try JSONDecoder().decode(
                AbsolutePathBuf.self,
                from: Data("\"project/file\"".utf8)
            )
            _ = guard_
            return (homePath, relativePath)
        }

        XCTAssertEqual(homePath.asPath, homeDir + "/code")
        XCTAssertEqual(relativePath.asPath, baseDir + "/project/file")
        XCTAssertThrowsError(
            try JSONDecoder().decode(AbsolutePathBuf.self, from: Data("\"project/file\"".utf8))
        )
    }

    func testNestedExplicitHomeDirectoriesRestoreThePreviousHome() throws {
        let outerHome = try tempdir()
        let innerHome = try tempdir()

        let (innerPath, restoredPath) = try AbsolutePathBufGuard.withHomeDirectory(outerHome) {
            let innerPath = try AbsolutePathBufGuard.withHomeDirectory(innerHome) {
                try AbsolutePathBuf.fromAbsolutePath("~/project")
            }
            let restoredPath = try AbsolutePathBuf.fromAbsolutePath("~/project")
            return (innerPath, restoredPath)
        }

        XCTAssertEqual(innerPath.asPath, innerHome + "/project")
        XCTAssertEqual(restoredPath.asPath, outerHome + "/project")
    }

    func testHomeDirectoryDoubleSlashIsExpandedInDeserialization() throws {
        guard let home = AbsolutePathBufGuard.homeDirectory() else { return }
        let baseDir = try tempdir()
        let guard_ = AbsolutePathBufGuard(basePath: baseDir)
        let absPathBuf = try JSONDecoder().decode(AbsolutePathBuf.self, from: Data("\"~//code\"".utf8))
        _ = guard_
        XCTAssertEqual(absPathBuf.asPath, home + "/code")
    }

    func testCanonicalizePreservingSymlinksKeepsLogicalSymlinkPath() throws {
        let baseDir = try tempdir()
        let real = baseDir + "/real"
        let link = baseDir + "/link"
        try FileManager.default.createDirectory(atPath: real, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: real)

        let canonicalized = try canonicalizePreservingSymlinks(link)
        XCTAssertEqual(canonicalized, link)
    }

    func testCanonicalizePreservingSymlinksKeepsLogicalMissingChildUnderSymlink() throws {
        let baseDir = try tempdir()
        let real = baseDir + "/real"
        let link = baseDir + "/link"
        try FileManager.default.createDirectory(atPath: real, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: real)
        let missing = link + "/missing.txt"

        let canonicalized = try canonicalizePreservingSymlinks(missing)
        XCTAssertEqual(canonicalized, missing)
    }

    func testCanonicalizeExistingPreservingSymlinksErrorsForMissingPath() throws {
        let baseDir = try tempdir()
        let missing = baseDir + "/missing"
        XCTAssertThrowsError(try canonicalizeExistingPreservingSymlinks(missing)) { error in
            XCTAssertEqual((error as? IOError)?.kind, .notFound)
        }
    }

    func testCanonicalizeExistingPreservingSymlinksKeepsLogicalSymlinkPath() throws {
        let baseDir = try tempdir()
        let real = baseDir + "/real"
        let link = baseDir + "/link"
        try FileManager.default.createDirectory(atPath: real, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: real)

        let canonicalized = try canonicalizeExistingPreservingSymlinks(link)
        XCTAssertEqual(canonicalized, link)
    }
}
