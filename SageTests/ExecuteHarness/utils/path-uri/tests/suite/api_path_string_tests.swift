//
//  api_path_string_tests.swift
//  SageTests
//
//  Port of codex-rs/utils/path-uri/src/api_path_string_tests.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Skipped upstream tests:
//  - `renders_native_non_unicode_windows_fallback_lossily` (`#[cfg(windows)]`,
//    plan §2.3).
//
//  `serde_json::from_value::<LegacyAppPathString>(json!(x))` maps to
//  `LegacyAppPathString.fromString(x)` inside table loops (the type is
//  `#[serde(transparent)]`); dedicated serde tests below exercise JSON
//  encoding/decoding directly. `Result` values are compared directly, like
//  upstream's `assert_eq!` on `Result<_, LegacyAppPathStringError>`.
//

import Foundation
@testable import CodexUtils
import XCTest

private enum ExpectedError {
    case opaqueFallback
    case incompatibleConvention
}

private enum RenderExpectation {
    case roundTrip(String)
    case renderOnly(String)
    case error(ExpectedError)
}

private struct RenderCase {
    let uri: String
    let convention: PathConvention
    let expected: RenderExpectation
}

// `RENDER_CASES` upstream.
private let renderCases: [RenderCase] = [
    // POSIX paths.
    RenderCase(uri: "file:///", convention: .posix, expected: .roundTrip("/")),
    RenderCase(uri: "file:///home/alice/src/main.rs", convention: .posix, expected: .roundTrip("/home/alice/src/main.rs")),
    RenderCase(uri: "file:///home/alice/a%20file.rs", convention: .posix, expected: .roundTrip("/home/alice/a file.rs")),
    RenderCase(uri: "file:///workspace/src/lib.rs", convention: .posix, expected: .roundTrip("/workspace/src/lib.rs")),
    RenderCase(uri: "file:///workspace/tests/test.rs", convention: .posix, expected: .roundTrip("/workspace/tests/test.rs")),
    RenderCase(uri: "file:///etc", convention: .posix, expected: .roundTrip("/etc")),
    RenderCase(uri: "file:///tmp/", convention: .posix, expected: .roundTrip("/tmp/")),
    RenderCase(uri: "file:///C:/Project", convention: .posix, expected: .renderOnly("/C:/Project")),
    RenderCase(uri: "file:///C:", convention: .posix, expected: .renderOnly("/C:")),
    RenderCase(uri: "file:///tmp/%E2%98%83", convention: .posix, expected: .roundTrip("/tmp/☃")),
    RenderCase(uri: "file:///tmp/a%5Cb", convention: .posix, expected: .roundTrip("/tmp/a\\b")),
    RenderCase(uri: "file:///tmp/100%25/file", convention: .posix, expected: .roundTrip("/tmp/100%/file")),
    RenderCase(uri: "file:///tmp/a%3Fb%23c%25d", convention: .posix, expected: .roundTrip("/tmp/a?b#c%d")),
    RenderCase(uri: "file:///tmp/a%252Fb", convention: .posix, expected: .roundTrip("/tmp/a%2Fb")),
    RenderCase(uri: "file:///bad/path/L3RtcC9udWxsLQAt_y1ieXRl", convention: .posix, expected: .roundTrip("/bad/path/L3RtcC9udWxsLQAt_y1ieXRl")),
    RenderCase(uri: "FILE:///workspace/src", convention: .posix, expected: .roundTrip("/workspace/src")),
    RenderCase(uri: "file:/workspace/src", convention: .posix, expected: .roundTrip("/workspace/src")),
    RenderCase(uri: "file://localhost/workspace/src", convention: .posix, expected: .roundTrip("/workspace/src")),
    RenderCase(uri: "file://LOCALHOST/workspace/src", convention: .posix, expected: .roundTrip("/workspace/src")),
    // Windows drive paths.
    RenderCase(uri: "file:///C:/Users/Alice%20Smith/src/main.rs", convention: .windows, expected: .roundTrip(#"C:\Users\Alice Smith\src\main.rs"#)),
    RenderCase(uri: "file:///C:/", convention: .windows, expected: .roundTrip("C:\\")),
    RenderCase(uri: "file:///C:", convention: .windows, expected: .renderOnly("C:\\")),
    RenderCase(uri: "file:///C:/Users", convention: .windows, expected: .roundTrip(#"C:\Users"#)),
    RenderCase(uri: "file:///C:/Windows", convention: .windows, expected: .roundTrip(#"C:\Windows"#)),
    RenderCase(uri: "file:///d:/snowman/%E2%98%83", convention: .windows, expected: .roundTrip("D:\\snowman\\☃")),
    RenderCase(uri: "file:///C:/tmp/", convention: .windows, expected: .roundTrip("C:\\tmp\\")),
    RenderCase(uri: "file:///C:/test%20with%20%25/path", convention: .windows, expected: .roundTrip(#"C:\test with %\path"#)),
    RenderCase(uri: "file:///C:/test%20with%20%2525/c%23code", convention: .windows, expected: .roundTrip(#"C:\test with %25\c#code"#)),
    RenderCase(uri: "file:///C:/Source/Z%C3%BCrich%20or%20Zurich%20(%CB%88zj%CA%8A%C9%99r%C9%AAk,/Code/resources/app/plugins/c%23/plugin.json", convention: .windows, expected: .roundTrip(#"C:\Source\Zürich or Zurich (ˈzjʊərɪk,\Code\resources\app\plugins\c#\plugin.json"#)),
    RenderCase(uri: "file:///C:/project/owner's_file/database.sqlite", convention: .windows, expected: .roundTrip(#"C:\project\owner's_file\database.sqlite"#)),
    RenderCase(uri: "file:///C:/project/%25A0.txt", convention: .windows, expected: .roundTrip(#"C:\project\%A0.txt"#)),
    RenderCase(uri: "file:///C:/project/%252e.txt", convention: .windows, expected: .roundTrip(#"C:\project\%2e.txt"#)),
    // Windows UNC paths.
    RenderCase(uri: "file://server/share/src/main.rs", convention: .windows, expected: .roundTrip(#"\\server\share\src\main.rs"#)),
    RenderCase(uri: "file://server/share", convention: .windows, expected: .roundTrip(#"\\server\share"#)),
    RenderCase(uri: "file://server/share/", convention: .windows, expected: .roundTrip("\\\\server\\share\\")),
    RenderCase(uri: "file://shares/files/c%23/p.cs", convention: .windows, expected: .roundTrip(#"\\shares\files\c#\p.cs"#)),
    RenderCase(uri: "file://monacotools1/certificates/SSL/", convention: .windows, expected: .roundTrip("\\\\monacotools1\\certificates\\SSL\\")),
    // Opaque fallbacks rendered according to their source convention.
    RenderCase(uri: "file:///%00/bad/path/L3RtcC9udWxsLQAt_y1ieXRl", convention: .posix, expected: .renderOnly("/tmp/null-\0-�-byte")),
    RenderCase(uri: "file:///%00/bad/path/XABcAC4AXABDAE8ATQAxAFwA", convention: .windows, expected: .roundTrip(#"\\.\COM1\"#)),
    RenderCase(uri: "file:///%00/bad/path/XABcAD8AXABWAG8AbAB1AG0AZQB7ADAAMAAwADAAMAAwADAAMAAtADAAMAAwADAALQAwADAAMAAwAC0AMAAwADAAMAAtADAAMAAwADAAMAAwADAAMAAwADAAMAAwAH0AXABmAGkAbABlAC4AcgBzAA", convention: .windows, expected: .roundTrip(#"\\?\Volume{00000000-0000-0000-0000-000000000000}\file.rs"#)),
    // Windows rendering preserves path text without filesystem validation.
    RenderCase(uri: "file:///C:/a%3Fb", convention: .windows, expected: .roundTrip("C:\\a?b")),
    RenderCase(uri: "file:///C:/a*b", convention: .windows, expected: .roundTrip("C:\\a*b")),
    RenderCase(uri: "file:///C:/trailing.", convention: .windows, expected: .roundTrip("C:\\trailing.")),
    RenderCase(uri: "file:///C:/trailing%20", convention: .windows, expected: .roundTrip("C:\\trailing ")),
    RenderCase(uri: "file:///C:/control-%01", convention: .windows, expected: .roundTrip("C:\\control-\u{1}")),
    RenderCase(uri: "file:///C:/file.txt:stream", convention: .windows, expected: .roundTrip("C:\\file.txt:stream")),
    RenderCase(uri: "file://server/sh%3Fare/file.rs", convention: .windows, expected: .roundTrip("\\\\server\\sh?are\\file.rs")),
    // These renderings intentionally lose URI byte or segment boundaries.
    RenderCase(uri: "file:///tmp/non-utf8-%FF", convention: .posix, expected: .renderOnly("/tmp/non-utf8-�")),
    RenderCase(uri: "file:///tmp/non-utf8-%A0", convention: .posix, expected: .renderOnly("/tmp/non-utf8-�")),
    RenderCase(uri: "file:///tmp/a%2Fb", convention: .posix, expected: .renderOnly("/tmp/a/b")),
    RenderCase(uri: "file:///C:/a%2Fb", convention: .windows, expected: .renderOnly("C:\\a/b")),
    RenderCase(uri: "file:///C:/a%5Cb", convention: .windows, expected: .renderOnly("C:\\a\\b")),
    // URI shapes that do not match the requested convention.
    RenderCase(uri: "file://server/share/file.txt", convention: .posix, expected: .error(.incompatibleConvention)),
    RenderCase(uri: "file://server/share/file.rs", convention: .posix, expected: .error(.incompatibleConvention)),
    RenderCase(uri: "file:///usr/local/file.txt", convention: .windows, expected: .error(.incompatibleConvention)),
    RenderCase(uri: "file:///home/alice/file.rs", convention: .windows, expected: .error(.incompatibleConvention)),
    RenderCase(uri: "file://server/", convention: .windows, expected: .error(.incompatibleConvention)),
    RenderCase(uri: "file:///_:/path", convention: .windows, expected: .error(.incompatibleConvention)),
    // Invalid opaque fallback payloads.
    RenderCase(uri: "file:///%00/bad/path/YQ", convention: .posix, expected: .error(.opaqueFallback)),
    RenderCase(uri: "file:///%00/bad/path/L3RtcC9udWxsLQAt_y1ieXRl", convention: .windows, expected: .error(.opaqueFallback)),
]

final class ApiPathStringTests: XCTestCase {

    func testRendersNativePathsFromSharedCases() throws {
        for testCase in renderCases {
            let path = try PathUri.parse(testCase.uri)
            let expected: Result<LegacyAppPathString, LegacyAppPathStringError>
            switch testCase.expected {
            case .roundTrip(let rendered), .renderOnly(let rendered):
                expected = .success(LegacyAppPathString(rendered))
            case .error(.opaqueFallback):
                expected = .failure(.opaqueFallback(path: path.description))
            case .error(.incompatibleConvention):
                expected = .failure(.incompatibleConvention(
                    path: path.description,
                    convention: testCase.convention
                ))
            }
            let actual: Result<LegacyAppPathString, LegacyAppPathStringError>
            do {
                actual = .success(try LegacyAppPathString.fromPathUri(path, convention: testCase.convention))
            } catch let error as LegacyAppPathStringError {
                actual = .failure(error)
            }
            XCTAssertEqual(actual, expected, "rendering \(testCase.uri) as \(testCase.convention)")
            if case .success(let rendered) = actual {
                XCTAssertEqual(
                    rendered.inferAbsolutePathConvention(),
                    testCase.convention,
                    "inferring \(testCase.uri)"
                )
            }

            if case .roundTrip(let rendered) = testCase.expected {
                let apiPath = LegacyAppPathString.fromString(rendered)
                let reparsed = try apiPath.toPathUri(testCase.convention)
                XCTAssertEqual(reparsed, path, "parsing \(testCase.uri)")
                try XCTAssertEqual(
                    try LegacyAppPathString.fromPathUri(reparsed, convention: testCase.convention),
                    apiPath,
                    "round-tripping \(testCase.uri)"
                )
            }
        }
    }

    func testRelativeApiPathSerializesAndDeserializesUnchanged() throws {
        // serde_json never escapes `/`; Foundation does unless told not to.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        for rawPath in [".", "subdir", "subdir/file.rs"] {
            let data = Data("\"\(rawPath)\"".utf8)
            let path = try JSONDecoder().decode(LegacyAppPathString.self, from: data)
            let encoded = try encoder.encode(path)
            XCTAssertEqual(String(decoding: encoded, as: UTF8.self), "\"\(rawPath)\"")
        }
    }

    func testRelativeApiPathIsInvalidWhenConvertedToAPathUri() throws {
        let rawPath = "subdir"
        let path = LegacyAppPathString.fromString(rawPath)

        XCTAssertNil(path.inferAbsolutePathConvention())
        XCTAssertThrowsError(try path.toPathUri(.posix)) { error in
            XCTAssertEqual(
                error as? LegacyAppPathStringError,
                .invalidNativePath(path: rawPath, convention: .posix)
            )
        }
        XCTAssertThrowsError(try PathUri(fromLegacy: path)) { error in
            XCTAssertEqual(
                error as? LegacyAppPathStringError,
                .invalidNativePath(path: rawPath, convention: nil)
            )
        }
        XCTAssertThrowsError(try AbsolutePathBuf(fromLegacy: path)) { error in
            XCTAssertEqual(
                error as? LegacyAppPathStringError,
                .invalidNativePath(path: rawPath, convention: nil)
            )
        }
    }

    func testOtherNonAbsoluteApiPathsCannotBeConvertedToPathUris() {
        for (rawPath, convention) in [
            (#"workspace\file.rs"#, PathConvention.windows),
            (#"C:file.rs"#, PathConvention.windows),
        ] {
            let path = LegacyAppPathString.fromString(rawPath)
            XCTAssertNil(path.inferAbsolutePathConvention())
            XCTAssertThrowsError(try path.toPathUri(convention)) { error in
                XCTAssertEqual(
                    error as? LegacyAppPathStringError,
                    .invalidNativePath(path: rawPath, convention: convention)
                )
            }
        }
    }

    func testInfersAbsolutePathConventionsFromApiText() {
        for (rawPath, expected) in [
            (#"C:\workspace\file.rs"#, PathConvention?.some(.windows)),
            ("c:/workspace/file.rs", .some(.windows)),
            (#"\\server\share\file.rs"#, .some(.windows)),
            (#"\\?\C:\workspace\file.rs"#, .some(.windows)),
            (#"\\.\COM1"#, .some(.windows)),
            ("/workspace/file.rs", .some(.posix)),
            ("/C:/workspace/file.rs", .some(.posix)),
            ("//server/share/file.rs", .some(.posix)),
            ("", nil),
            (".", nil),
            ("subdir/file.rs", nil),
            (#"subdir\file.rs"#, nil),
            (#"C:file.rs"#, nil),
            (#"\rooted-without-drive"#, nil),
        ] {
            let path = LegacyAppPathString.fromString(rawPath)
            XCTAssertEqual(path.inferAbsolutePathConvention(), expected, "inferring \(rawPath)")
        }
    }

    func testConvertsAbsoluteApiPathsUsingTheInferredConvention() throws {
        for (rawPath, convention, expectedUri) in [
            (#"C:\workspace\file.rs"#, PathConvention.windows, "file:///C:/workspace/file.rs"),
            ("/workspace/file.rs", PathConvention.posix, "file:///workspace/file.rs"),
        ] {
            let path = LegacyAppPathString.fromString(rawPath)
            try XCTAssertEqual(path.toInferredPathUri(), try PathUri.parse(expectedUri))
            XCTAssertEqual(path.renderForUi(), rawPath)
            try XCTAssertEqual(try PathUri(fromLegacy: path), try path.toPathUri(convention))
        }
    }

    func testResolvesLegacyPathsAgainstExecutorContext() throws {
        for (cwd, path, userHomeDir, expected) in [
            ("file:///workspace", "relative.txt", String?.none, "file:///workspace/relative.txt"),
            ("file:///C:/workspace", "/Windows", nil, "file:///C:/Windows"),
            ("file:///C:/workspace", "//server/share/file.txt", nil, "file://server/share/file.txt"),
            ("file:///workspace", "~//notes", .some("file:///home/executor"), "file:///home/executor/notes"),
            ("file:///C:/workspace", #"~\\notes"#, .some("file:///C:/Users/executor"), "file:///C:/Users/executor/notes"),
        ] {
            let cwdUri = try PathUri.parse(cwd)
            let homeUri = try userHomeDir.map { try PathUri.parse($0) }
            try XCTAssertEqual(
                try LegacyAppPathString.fromString(path).resolveAgainst(cwd: cwdUri, userHomeDir: homeUri),
                try PathUri.parse(expected),
                "resolving \(path) against \(cwd)"
            )
        }
    }

    func testRejectsLegacyPathsWithoutExecutorContext() throws {
        let cwd = try PathUri.parse("file:///workspace")

        XCTAssertThrowsError(
            try LegacyAppPathString.fromString(#"C:\\tmp"#).resolveAgainst(cwd: cwd, userHomeDir: nil)
        ) { error in
            XCTAssertEqual(
                error as? LegacyAppPathStringError,
                .mismatchedConvention(
                    path: #"C:\\tmp"#,
                    pathConvention: .windows,
                    cwd: cwd.description,
                    convention: .posix
                )
            )
        }
        XCTAssertThrowsError(
            try LegacyAppPathString.fromString("~/secret").resolveAgainst(cwd: cwd, userHomeDir: nil)
        ) { error in
            XCTAssertEqual(
                error as? LegacyAppPathStringError,
                .missingHomeDirectory(path: "~/secret")
            )
        }
    }

    func testAmbiguousAbsoluteApiPathsPreserveTheirInferredConvention() throws {
        for (rawPath, convention) in [
            ("/C:/secret", PathConvention.posix),
            (#"\\localhost\share"#, PathConvention.windows),
        ] {
            let path = LegacyAppPathString.fromString(rawPath)
            let uri = try PathUri(fromLegacy: path)
            XCTAssertEqual(uri.inferPathConvention(), convention)
            XCTAssertEqual(LegacyAppPathString(uri), path)
        }
    }

    func testConvertsNativeApiPathToInferredAbsolutePath() throws {
        // `#[cfg(not(windows))]` path upstream.
        let rawPath = "/workspace/file.rs"
        let path = LegacyAppPathString.fromString(rawPath)
        let expected = try AbsolutePathBuf.fromAbsolutePathChecked(rawPath)
        try XCTAssertEqual(try AbsolutePathBuf(fromLegacy: path), expected)
        XCTAssertEqual(path.toInferredAbsPath(), expected)
    }

    func testForeignAbsoluteSyntaxDeserializesWithoutHostInterpretation() {
        for (rawPath, convention) in [
            (#"C:\workspace\file.rs"#, PathConvention.windows),
            ("/workspace/file.rs", PathConvention.posix),
        ] {
            let path = LegacyAppPathString.fromString(rawPath)
            XCTAssertEqual(path.asStr(), rawPath)
            XCTAssertEqual(path.inferAbsolutePathConvention(), convention)
        }
    }

    func testFromPathPreservesForeignAbsolutePathForUriConversion() throws {
        // `#[cfg(not(windows))]` pair upstream.
        let (foreignPath, expectedUri) = (#"C:\Users\openai\share"#, "file:///C:/Users/openai/share")
        let path = try PathUri(fromLegacy: LegacyAppPathString.fromPath(foreignPath))
        try XCTAssertEqual(path, try PathUri.parse(expectedUri))
    }

    func testRendersAnAbsolutePathUsingTheHostConvention() throws {
        // `#[cfg(unix)]` path upstream.
        let nativePath = "/workspace/a file.rs"
        let path = try AbsolutePathBuf.fromAbsolutePathChecked(nativePath)
        XCTAssertEqual(LegacyAppPathString(path), LegacyAppPathString(nativePath))
    }

    func testSerializesAndDeserializesAsAString() throws {
        let path = try PathUri.parse("file:///workspace/src/lib.rs")
        let rendered = try LegacyAppPathString.fromPathUri(path, convention: .posix)
        // serde_json never escapes `/`; Foundation does unless told not to.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let data = try encoder.encode(rendered)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "\"/workspace/src/lib.rs\"")
        try XCTAssertEqual(
            try JSONDecoder().decode(LegacyAppPathString.self, from: data),
            rendered
        )
    }
}
