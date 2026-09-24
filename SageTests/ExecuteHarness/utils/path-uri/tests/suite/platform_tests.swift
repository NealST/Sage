//
//  platform_tests.swift
//  SageTests
//
//  Port of codex-rs/utils/path-uri/src/platform_tests.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  Coverage for platform metadata and platform-derived path conventions.
//

import Foundation
@testable import CodexUtils
import XCTest

final class PlatformTests: XCTestCase {

    func testPlatformMetadataPreservesMissingAndUnrecognizedValues() {
        for (metadata, expected) in [
            (String?.some("linux"), Platform.linux),
            (.some("macos"), .macos),
            (.some("windows"), .windows),
            (nil, .unknown),
            (.some("freebsd"), .unknown),
            (.some("Windows"), .unknown),
            (.some(""), .unknown),
        ] {
            XCTAssertEqual(Platform.fromPlatformOs(metadata), expected, "\(String(describing: metadata))")
        }
    }

    func testPathConventionIsDerivedFromPlatform() {
        for (platform, expected) in [
            (Platform.linux, PathConvention?.some(.posix)),
            (.macos, .some(.posix)),
            (.windows, .some(.windows)),
            (.unknown, nil),
        ] {
            XCTAssertEqual(platform.pathConvention(), expected, "\(platform)")
        }
    }

    func testNativePlatformMatchesCurrentProcessMetadata() {
        // `std::env::consts::OS` is "macos" on this host.
        XCTAssertEqual(Platform.native(), Platform.fromPlatformOs("macos"))
    }
}
