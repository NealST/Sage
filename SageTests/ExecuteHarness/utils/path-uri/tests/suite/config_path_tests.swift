//
//  config_path_tests.swift
//  SageTests
//
//  Port of codex-rs/utils/path-uri/src/config_path_tests.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  The configuration boundary shares URI resolution and rejects lossy
//  denials. `Result::is_err` maps to `XCTAssertThrowsError`;
//  `Result::ok().as_deref()` maps to `try?`.
//

import Foundation
@testable import CodexUtils
import XCTest

final class ConfigPathTests: XCTestCase {

    func testConfigurationPathsResolveWithTheSuppliedPlatformAndHome() throws {
        for (convention, base, home, input, expected, expectedUri) in [
            (
                PathConvention.posix,
                "file:///work/project",
                "file:///home/user",
                "~/a b/雪%/",
                "/home/user/a b/雪%",
                "file:///home/user/a%20b/%E9%9B%AA%25"
            ),
            (
                PathConvention.posix,
                "file:///work/project",
                "file:///home/user",
                "/",
                "/",
                "file:///"
            ),
            (
                PathConvention.windows,
                "file:///C:/work/project",
                "file:///C:/Users/user",
                #"..\private\"#,
                #"C:\work\private"#,
                "file:///C:/work/private"
            ),
            (
                PathConvention.windows,
                "file:///C:/work/project",
                "file:///C:/Users/user",
                #"d:\private\*.env\"#,
                #"D:\private\*.env"#,
                "file:///D:/private/*.env"
            ),
            (
                PathConvention.windows,
                "file:///C:/work/project",
                "file:///C:/Users/user",
                #"D:\"#,
                #"D:\"#,
                "file:///D:"
            ),
            (
                PathConvention.windows,
                "file:///C:/work/project",
                "file:///C:/Users/user",
                #"~\a b\雪%\"#,
                #"C:\Users\user\a b\雪%"#,
                "file:///C:/Users/user/a%20b/%E9%9B%AA%25"
            ),
            (
                PathConvention.windows,
                "file:///C:/work",
                "file:///C:/Users/user",
                #"\\SERVER\Share\private\*.env\"#,
                #"\\server\Share\private\*.env"#,
                "file://server/Share/private/*.env"
            ),
            (
                PathConvention.windows,
                "file:///C:/work",
                "file:///C:/Users/user",
                #"\\server\share"#,
                #"\\server\share\"#,
                "file://server/share"
            ),
        ] {
            let baseUri = try PathUri.parse(base)
            let homeUri = try PathUri.parse(home)
            try XCTAssertEqual(
                try PathUri.resolveConfigPathUri(
                    input: input,
                    convention: convention,
                    base: baseUri,
                    userHomeDir: homeUri
                ),
                try PathUri.parse(expectedUri),
                rustDebugString(input)
            )
            try XCTAssertEqual(
                try PathUri.resolveConfigPath(
                    input: input,
                    convention: convention,
                    base: baseUri,
                    userHomeDir: homeUri
                ),
                expected,
                rustDebugString(input)
            )
            if (!input.hasPrefix(".") && !input.hasPrefix("\\")) || input.hasPrefix("\\\\") {
                try XCTAssertEqual(
                    try PathUri.resolveConfigPath(
                        input: input,
                        convention: convention,
                        base: nil,
                        userHomeDir: homeUri
                    ),
                    expected,
                    "without base: \(rustDebugString(input))"
                )
            }
        }
    }

    func testConfigurationPathsRejectAmbiguousOrLossyDenials() throws {
        for (convention, base) in [
            (PathConvention.posix, "file:///base/%FF"),
            (PathConvention.posix, "file:///base/encoded%2Fname"),
            (PathConvention.posix, "file:///C:/base"),
            (PathConvention.windows, "file:///base"),
            (PathConvention.windows, "file:///C:/encoded%5Cname"),
            (PathConvention.windows, "file:///C:/%FF"),
            (PathConvention.windows, "file:///C:/base/a:b"),
        ] {
            let baseUri = try PathUri.parse(base)
            XCTAssertThrowsError(try baseUri.validateConfigPath(convention: convention), base)
        }
        let base = try PathUri.parse("file:///base")
        let opaque = PathUri.fromOpaquePathBytes([UInt8]("/base".utf8))
        for input in ["nul\0", "nul\0/../private", "/nul\0", "~/private"] {
            XCTAssertThrowsError(
                try PathUri.resolveConfigPath(
                    input: input,
                    convention: .posix,
                    base: base,
                    userHomeDir: nil
                ),
                input
            )
        }
        XCTAssertThrowsError(
            try PathUri.resolveConfigPath(
                input: "child",
                convention: .posix,
                base: opaque,
                userHomeDir: nil
            )
        )
        for input in [
            #"\\server\.\private"#,
            #"\\server\..\private"#,
            #"\\.\COM1"#,
            #"C:\private\file:stream"#,
            #"C:\base\a:b\..\private"#,
        ] {
            XCTAssertThrowsError(
                try PathUri.resolveConfigPath(
                    input: input,
                    convention: .windows,
                    base: nil,
                    userHomeDir: nil
                ),
                input
            )
        }
        let home = try PathUri.parse("file:///C:/Users/user")
        for input in [
            "C:",
            #"~/\private"#,
            #"~\/private"#,
            #"\\0x7f000001\share\private"#,
            #"\\bücher\share\private"#,
        ] {
            XCTAssertThrowsError(
                try PathUri.resolveConfigPath(
                    input: input,
                    convention: .windows,
                    base: home,
                    userHomeDir: home
                ),
                input
            )
        }
        // Unused facts cannot change an already absolute path.
        try XCTAssertEqual(
            try PathUri.resolveConfigPath(
                input: "/private",
                convention: .posix,
                base: opaque,
                userHomeDir: opaque
            ),
            "/private"
        )
    }

    func testGlobResolutionRejectsMetacharactersInUsedDirectoryFacts() throws {
        for (convention, prefix, separator) in [
            (PathConvention.posix, "/home/", "/"),
            (PathConvention.windows, #"C:\Users\"#, #"\"#),
        ] {
            let clean = try LegacyAppPathString.fromString("\(prefix)sam")
                .toPathUri(convention)
            for name in ["sam[1]", "sam{1,2}"] {
                let directory = try LegacyAppPathString.fromString("\(prefix)\(name)")
                    .toPathUri(convention)
                // The directory remains valid as a literal path, and unused
                // facts cannot reject an absolute pattern supplied by the user.
                let absolute = "\(prefix)ordinary\(separator)*.key"
                let literal = "\(prefix)\(name)\(separator)private\(separator)key"
                for (input, base, home, expected) in [
                    ("private/*.key", directory, PathUri?.none, String?.none),
                    ("~/private/*.key", clean, .some(directory), nil),
                    ("private/key", directory, nil, .some(literal)),
                    (absolute, directory, .some(directory), .some(absolute)),
                ] {
                    XCTAssertEqual(
                        try? PathUri.resolveConfigPath(
                            input: input,
                            convention: convention,
                            base: base,
                            userHomeDir: home
                        ),
                        expected,
                        "\(convention): \(name): \(input)"
                    )
                }
            }
            try XCTAssertEqual(
                try PathUri.resolveConfigPath(
                    input: "~/private/*.key",
                    convention: convention,
                    base: clean,
                    userHomeDir: clean
                ),
                "\(prefix)sam\(separator)private\(separator)*.key"
            )
        }
    }

    func testGlobDirectoryValidationRejectsPosixEscapeCharacters() throws {
        let directory = try LegacyAppPathString.fromString(#"/home/sam\name"#)
            .toPathUri(.posix)
        XCTAssertThrowsError(try directory.validateGlobDirectory(convention: .posix))
    }
}
