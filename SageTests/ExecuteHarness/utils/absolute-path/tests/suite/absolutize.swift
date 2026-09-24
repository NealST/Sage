//
//  absolutize.swift
//  SageTests
//
//  Port of codex-rs/utils/absolute-path/src/absolutize.rs #[cfg(test)] (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  Unix tests only; the two `#[cfg(windows)]` tests are excluded (plan §2.3).
//

import XCTest
@testable import CodexUtils

final class AbsolutizeTests: XCTestCase {
    func testAbsolutePathWithoutDotsIsUnchanged() {
        XCTAssertEqual(
            absolutizeFrom("/path/to/123/456", basePath: "/base"),
            "/path/to/123/456"
        )
    }

    func testAbsolutePathDotsAreRemoved() {
        XCTAssertEqual(
            absolutizeFrom("/path/to/./123/../456", basePath: "/base"),
            "/path/to/456"
        )
    }

    func testRelativePathWithoutDotUsesBase() {
        XCTAssertEqual(
            absolutizeFrom("path/to/123/456", basePath: "/base"),
            "/base/path/to/123/456"
        )
    }

    func testRelativePathWithCurrentDirUsesBase() {
        XCTAssertEqual(
            absolutizeFrom("./path/to/123/456", basePath: "/base"),
            "/base/path/to/123/456"
        )
    }

    func testRelativePathWithParentDirUsesBaseParent() {
        XCTAssertEqual(
            absolutizeFrom("../path/to/123/456", basePath: "/base/cwd"),
            "/base/path/to/123/456"
        )
    }

    func testParentDirAboveRootStaysAtRoot() {
        XCTAssertEqual(
            absolutizeFrom("../../path/to/123/456", basePath: "/"),
            "/path/to/123/456"
        )
    }

    func testEmptyPathUsesBase() {
        XCTAssertEqual(
            absolutizeFrom("", basePath: "/base/cwd"),
            "/base/cwd"
        )
    }
}
