//
//  home_dir_lib_tests.swift
//  SageTests
//
//  Port of codex-rs/utils/home-dir/src/lib.rs #[cfg(test)] (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  `tempfile::TempDir` maps to a unique directory under
//  NSTemporaryDirectory. `err.kind()` maps to `IOError.kind`;
//  `err.to_string()` maps to `IOError.description`.
//

import Foundation
import XCTest
@testable import SageUtils

final class FindSageHomeTests: XCTestCase {

    /// `tempfile::tempdir`.
    private func tempdir() throws -> String {
        let dir = NSTemporaryDirectory() + "home-dir-tests-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    /// `find_sage_home_env_missing_path_is_fatal`.
    func testFindSageHomeEnvMissingPathIsFatal() throws {
        let tempHome = try tempdir()
        let missing = tempHome + "/missing-sage-home"

        XCTAssertThrowsError(try findSageHomeFromEnv(missing)) { error in
            guard let ioError = error as? IOError else {
                XCTFail("unexpected error type: \(error)")
                return
            }
            XCTAssertEqual(ioError.kind, .notFound)
            XCTAssertTrue(
                ioError.description.contains("SAGE_HOME"),
                "unexpected error: \(ioError)"
            )
        }
    }

    /// `find_sage_home_env_file_path_is_fatal`.
    func testFindSageHomeEnvFilePathIsFatal() throws {
        let tempHome = try tempdir()
        let filePath = tempHome + "/sage-home.txt"
        try "not a directory".write(toFile: filePath, atomically: false, encoding: .utf8)

        XCTAssertThrowsError(try findSageHomeFromEnv(filePath)) { error in
            guard let ioError = error as? IOError else {
                XCTFail("unexpected error type: \(error)")
                return
            }
            XCTAssertEqual(ioError.kind, .invalidInput)
            XCTAssertTrue(
                ioError.description.contains("not a directory"),
                "unexpected error: \(ioError)"
            )
        }
    }

    /// `find_sage_home_env_valid_directory_canonicalizes`.
    func testFindSageHomeEnvValidDirectoryCanonicalizes() throws {
        let tempHome = try tempdir()

        let resolved = try findSageHomeFromEnv(tempHome)
        let expected = try AbsolutePathBuf.fromAbsolutePath(realpathString(tempHome))
        XCTAssertEqual(resolved, expected)
    }

    /// `find_sage_home_without_env_uses_default_home_dir`.
    func testFindSageHomeWithoutEnvUsesDefaultHomeDir() throws {
        let resolved = try findSageHomeFromEnv(nil)
        let home = try XCTUnwrap(AbsolutePathBufGuard.homeDirectory(), "home dir")
        let expected = try AbsolutePathBuf.fromAbsolutePath(home + "/.sage")
        XCTAssertEqual(resolved, expected)
    }
}
