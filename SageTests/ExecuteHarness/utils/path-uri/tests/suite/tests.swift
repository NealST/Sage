//
//  tests.swift
//  SageTests
//
//  Port of codex-rs/utils/path-uri/src/tests.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Unix subset. Skipped upstream tests (documented gaps):
//  - `file_uri_falls_back_for_posix_paths_with_null_bytes` and
//    `file_uri_accepts_non_utf8_posix_paths`: the upstream paths contain a
//    raw 0xFF byte, which the String-based `AbsolutePathBuf` cannot
//    represent (see path-uri/src/path_uri_lib.swift header).
//  - `#[cfg(windows)]` tests (`file_uri_falls_back_for_windows_prefixes…`,
//    `file_uri_fallback_round_trips_non_unicode_windows_paths`,
//    `file_uri_round_trips_windows_unc_paths`) per plan §2.3.
//  - The `#[cfg(windows)]` `to_abs_path` assertion inside
//    `windows_uri_native_conversion_rejects_encoded_separators`.
//
//  `Result<T, E>` values are compared directly where upstream asserts
//  `Ok(...)`; `expect_err` assertions use `XCTAssertThrowsError` + typed
//  equality. `io::Error::to_string()` maps to `IOError.message` (its
//  `description` is the message, matching Rust's `Display`).
//

import Foundation
@testable import CodexUtils
import XCTest

final class PathUriTests: XCTestCase {

    func testNativeByteJoinsPreserveForeignPosixFilenames() throws {
        let base = try PathUri.parse("file:///root/%FE/admin")
        for (path, expected) in [
            (
                [UInt8]("../".utf8) + [0xFF] + [UInt8]("/%2e?#\\".utf8),
                "file:///root/%FE/%FF/%252e%3F%23%5C"
            ),
            (
                [UInt8]("//other/./x/../".utf8) + [0xFF] + [UInt8]("/.git".utf8),
                "file:///other/%FF/.git"
            ),
            (
                [UInt8]("../../../../".utf8) + [0xFF],
                "file:///%FF"
            ),
            ([UInt8]("../plain".utf8), "file:///root/%FE/plain"),
        ] {
            try XCTAssertEqual(try base.joinNativeBytes(path).description, expected)
        }
        XCTAssertThrowsError(try base.joinNativeBytes([UInt8]("bad\0".utf8) + [0xFF]))
        XCTAssertThrowsError(
            try PathUri.parse("file:///C:/repo").joinNativeBytes([0xFF])
        )
    }

    func testFileUriRoundTripsAnAbsolutePath() throws {
        let path = try AbsolutePathBuf.currentDir().join("a path/file.rs")

        let uri = PathUri.fromAbsPath(path)

        let uriString = uri.description
        XCTAssertTrue(uriString.hasPrefix("file:"))
        XCTAssertTrue(uriString.hasSuffix("/a%20path/file.rs"))
        try XCTAssertEqual(try PathUri.parse(uriString), uri)
        try XCTAssertEqual(try uri.toAbsPath(), path)
    }

    func testNonNativeUriIoConversionIsInvalidInput() throws {
        // `#[cfg(unix)]` URI set upstream.
        for uriString in ["file://server/share/file.txt", "file:///C:/workspace"] {
            let uri = try PathUri.parse(uriString)
            XCTAssertThrowsError(try uri.toAbsPath()) { error in
                guard let ioError = error as? IOError else {
                    XCTFail("expected IOError, got \(error)")
                    return
                }
                XCTAssertEqual(ioError.kind, .invalidInput)
                XCTAssertEqual(ioError.message, "'\(uri)' is invalid on 'macos'")
            }
        }
    }

    func testWindowsUriNativeConversionRejectsEncodedSeparators() throws {
        for uriString in [
            "file:///C%3A/plugins/demo/..%5Coutside.json",
            "file:///C%3a/plugins/demo/..%5coutside.json",
            "file:///C:/plugins/demo/..%2Foutside.json",
            "file://server/share/plugins/demo/..%5Coutside.json",
        ] {
            let uri = try PathUri.parse(uriString)
            XCTAssertEqual(uri.inferPathConvention(), .windows)
            XCTAssertNil(containmentPathSegments(uri.url, .windows))
            // The `#[cfg(windows)]` to_abs_path rejection is not applicable.
        }
    }

    func testFileUriParsesAWindowsPathOnAnyHost() throws {
        let uri = try PathUri.parse("file:///C:/Users/Alice%20Smith/src/main.rs")
        XCTAssertEqual(uri.encodedPath(), "/C:/Users/Alice%20Smith/src/main.rs")
        XCTAssertEqual(uri.basename(), "main.rs")
        XCTAssertEqual(uri.description, "file:///C:/Users/Alice%20Smith/src/main.rs")
    }

    func testFileUriNormalizesWindowsDriveLetterCase() throws {
        let lowercase = try PathUri.parse("file:///c:/Users/Alice%20Smith/src/main.rs")
        let uppercase = try PathUri.parse("file:///C:/Users/Alice%20Smith/src/main.rs")
        XCTAssertEqual(lowercase, uppercase)
        XCTAssertEqual(lowercase.description, "file:///C:/Users/Alice%20Smith/src/main.rs")
    }

    func testPathUriEqualityAndHashingFollowPathConvention() throws {
        for (left, right, expected) in [
            ("file:///C:/Users/Alice", "file:///c:/users/ALICE", true),
            ("file://SERVER/SHARE/Project", "file://server/share/project", true),
            ("file:///home/Alice", "file:///home/alice", false),
            ("file:///C:/plugins/ǈ", "file:///C:/plugins/Ǉ", false),
            ("file:///C:/plugins/%41", "file:///C:/plugins/a", true),
            ("file:///C:/plugins/a%2Fb", "file:///C:/plugins/a/b", false),
            ("file:///%00/bad/path/YQ", "file:///%00/bad/path/yQ", false),
        ] {
            let leftUri = try PathUri.parse(left)
            let rightUri = try PathUri.parse(right)
            XCTAssertEqual(leftUri == rightUri, expected, "comparing \(right)")
            XCTAssertEqual(Set([leftUri]).contains(rightUri), expected, "hashing \(right)")
        }
    }

    func testInfersPathConventionsFromUriShape() throws {
        for (uri, expected) in [
            ("file:///", PathConvention?.some(.posix)),
            ("file:///home/alice/src", .some(.posix)),
            ("file:///C:/Users/Alice/src", .some(.windows)),
            ("file:///d:", .some(.windows)),
            ("file:///c%3A/Users/Alice/src", .some(.windows)),
            ("file:///D%3a/Users/Alice/src", .some(.windows)),
            ("file://server/share/src", .some(.windows)),
            // Opaque fallback for POSIX bytes `/tmp/null-\0-\xff-byte`.
            ("file:///%00/bad/path/L3RtcC9udWxsLQAt_y1ieXRl", .some(.posix)),
            // Opaque fallback for Windows UTF-16LE `\\.\COM1\`.
            ("file:///%00/bad/path/XABcAC4AXABDAE8ATQAxAFwA", .some(.windows)),
            ("file:///%00/bad/path/YQ", nil),
        ] {
            let path = try PathUri.parse(uri)
            XCTAssertEqual(path.inferPathConvention(), expected, "inferring \(uri)")
        }
    }

    func testPathConventionSplitsAbsoluteRelativeAndBarePathText() {
        for (convention, path, expected) in [
            (PathConvention.posix, "/usr/local/bin/bash", ["", "usr", "local", "bin", "bash"]),
            (PathConvention.posix, #"tools\pwsh.exe"#, [#"tools\pwsh.exe"#]),
            (
                PathConvention.windows,
                #"C:\Program Files\PowerShell\7\pwsh.exe"#,
                ["C:", "Program Files", "PowerShell", "7", "pwsh.exe"]
            ),
            (PathConvention.windows, "tools/pwsh.exe", ["tools", "pwsh.exe"]),
            (PathConvention.windows, "cmd.exe", ["cmd.exe"]),
        ] {
            XCTAssertEqual(convention.pathSegments(path), expected)
        }
    }

    func testDriveShapedPosixUriIsIntentionallyInferredAsWindows() throws {
        let path = try PathUri.parse("file:///C:/actually/a/posix/path")
        XCTAssertEqual(path.inferPathConvention(), .windows)
    }

    func testInferredNativePathStringUsesTheInferredConvention() throws {
        for (uri, expected) in [
            ("file:///home/alice/a%20file.rs", "/home/alice/a file.rs"),
            ("file:///C:/Users/Alice%20Smith/main.rs", #"C:\Users\Alice Smith\main.rs"#),
            ("file:///c%3A/Users/Alice/src/main.rs", #"C:\Users\Alice\src\main.rs"#),
            ("file://server/share/main.rs", #"\\server\share\main.rs"#),
            ("file://server/", "file://server/"),
            ("file:///%00/bad/path/YQ", "file:///%00/bad/path/YQ"),
        ] {
            let path = try PathUri.parse(uri)
            XCTAssertEqual(path.inferredNativePathString(), expected, "rendering \(uri)")
            XCTAssertEqual(
                LegacyAppPathString(path).asStr(),
                expected,
                "rendering typed API path \(uri)"
            )
        }
    }

    func testRelativePathFromIsHostIndependent() throws {
        // `file://abc/...` has an authority and is inferred as Windows UNC,
        // while `file:///abc/...` is hostless and inferred as POSIX.
        for (path, base, expected) in [
            (
                "file:///home/alice/project/src/a%20file.rs",
                "file:///home/alice/project",
                String?.some("src/a file.rs")
            ),
            (
                "file:///c:/Users/Alice/project/src/main.rs",
                "file:///C:/Users/Alice/project",
                .some(#"src\main.rs"#)
            ),
            (
                "file:///C:/USERS/%C3%84/PROJECT/src/main.rs",
                "file:///c:/users/%C3%A4/project",
                nil
            ),
            (
                "file://server/share/project/src/main.rs",
                "file://server/share/project",
                .some(#"src\main.rs"#)
            ),
            (
                "file://SERVER/SHARE/PROJECT/src/main.rs",
                "file://server/share/project",
                .some(#"src\main.rs"#)
            ),
            (
                "file:///home/alice/project",
                "file:///home/alice/project/",
                .some("")
            ),
            (
                "file:///home/alice/project-two/main.rs",
                "file:///home/alice/project",
                nil
            ),
            ("file:///HOME/alice/project", "file:///home", nil),
            (
                "file://other/share/project/main.rs",
                "file://server/share/project",
                nil
            ),
            (
                "file:///home/alice/project/src%2Fmain.rs",
                "file:///home/alice/project",
                nil
            ),
            (
                "file:///C:/project/src%5Cmain.rs",
                "file:///C:/project",
                nil
            ),
            ("file:///C:/project/main.rs", "file:///", nil),
        ] {
            let pathUri = try PathUri.parse(path)
            let baseUri = try PathUri.parse(base)
            XCTAssertEqual(
                pathUri.relativePathFrom(baseUri),
                expected,
                "finding \(path) relative to \(base)"
            )
        }
    }

    func testRelativePathFromTreatsFallbackUrisAsOpaque() throws {
        let path = try PathUri.parse("file:///%00/bad/path/YQ")
        let other = try PathUri.parse("file:///%00/bad/path/Yg")
        let root = try PathUri.parse("file:///")
        XCTAssertEqual(path.relativePathFrom(path), "")
        XCTAssertNil(path.relativePathFrom(other))
        XCTAssertNil(path.relativePathFrom(root))
    }

    func testOrdinaryBadPathUriIsNotDecodedAsAFallback() throws {
        // `#[cfg(unix)]` upstream.
        let path = try AbsolutePathBuf.fromAbsolutePathChecked("/bad/path/L3RtcC9udWxsLQAt_y1ieXRl")
        let uri = PathUri.fromAbsPath(path)
        XCTAssertEqual(uri.description, "file:///bad/path/L3RtcC9udWxsLQAt_y1ieXRl")
        try XCTAssertEqual(try uri.toAbsPath(), path)
    }

    func testMalformedBadPathUrisAreRejected() {
        for uri in [
            "file:///%00/bad/path/",
            "file:///%00/bad/path/not*base64",
            "file:///%00/bad/path/YQ==",
            "file:///%00/bad/path/YR",
            "file:///%00/bad/path/YQ/extra",
            "file:///%00/other/YQ",
        ] {
            XCTAssertThrowsError(try PathUri.parse(uri), "parsing \(uri)") { error in
                XCTAssertEqual(
                    error as? PathUriParseError,
                    .invalidFileUriPath(path: uri),
                    "parsing \(uri)"
                )
            }
        }
    }

    func testStructurallyValidBadPathUriWithInvalidNativePayloadFailsConversion() throws {
        let uri = try PathUri.parse("file:///%00/bad/path/YQ")
        XCTAssertThrowsError(try uri.toAbsPath()) { error in
            XCTAssertEqual((error as? IOError)?.kind, .invalidInput)
        }
    }

    func testBadPathUrisAreOpaqueToLexicalOperations() throws {
        let uri = try PathUri.parse("file:///%00/bad/path/YQ")
        let other = try PathUri.parse("file:///%00/bad/path/Yg")
        let root = try PathUri.parse("file:///")

        XCTAssertNil(uri.basename())
        XCTAssertNil(uri.parent())
        XCTAssertTrue(uri.startsWith(uri))
        XCTAssertFalse(uri.startsWith(root))
        XCTAssertFalse(uri.startsWith(other))
        XCTAssertFalse(other.startsWith(uri))
        try XCTAssertEqual(try uri.join(""), uri)
        XCTAssertThrowsError(try uri.join("child")) { error in
            XCTAssertEqual(
                error as? PathUriParseError,
                .invalidFileUriPath(path: uri.description)
            )
        }
    }

    func testFileUriParsesAPosixPathOnAnyHost() throws {
        let uri = try PathUri.parse("file:///home/alice/src/main.rs")
        XCTAssertEqual(uri.encodedPath(), "/home/alice/src/main.rs")
        XCTAssertEqual(uri.basename(), "main.rs")
        XCTAssertEqual(uri.description, "file:///home/alice/src/main.rs")
    }

    func testFileUriPreservesPathsThatResembleWindowsPaths() throws {
        for (input, expectedPath) in [("file:///C:/Project", "/C:/Project"), ("file:///C:", "/C:")] {
            let uri = try PathUri.parse(input)
            let reparsed = try PathUri.parse(uri.description)
            XCTAssertEqual(uri.encodedPath(), expectedPath)
            XCTAssertEqual(reparsed, uri)
        }
    }

    func testFileUriRoundTripsLiteralPercentCharacters() throws {
        let uri = try PathUri.parse("file:///tmp/100%25/file")
        XCTAssertEqual(uri.description, "file:///tmp/100%25/file")
        XCTAssertEqual(uri.encodedPath(), "/tmp/100%25/file")
        XCTAssertEqual(uri.basename(), "file")
    }

    func testFileUriRetainsUncAuthority() throws {
        let uri = try PathUri.parse("file://server/share/src/main.rs")
        XCTAssertEqual(uri.encodedPath(), "/share/src/main.rs")
        XCTAssertEqual(uri.description, "file://server/share/src/main.rs")
    }

    func testFileUriSpellingAliasesHaveOneCanonicalForm() throws {
        for input in [
            "FILE:///workspace/src",
            "file:/workspace/src",
            "file://localhost/workspace/src",
            "file://LOCALHOST/workspace/src",
        ] {
            let uri = try PathUri.parse(input)
            XCTAssertEqual(uri.description, "file:///workspace/src", "parsing \(input)")
        }
    }

    func testUnsupportedSchemesAreRejectedAtConstruction() {
        for (input, expectedScheme) in [
            ("codex-env:///devbox/workspace", "codex-env"),
            ("artifact://store/object-1", "artifact"),
            ("http://example.com/file", "http"),
            ("https://example.com/file", "https"),
            ("ssh://host/workspace", "ssh"),
            ("vscode-remote://ssh-remote+host/workspace", "vscode-remote"),
            ("untitled:Untitled-1", "untitled"),
        ] {
            XCTAssertThrowsError(try PathUri.parse(input), "parsing \(input)") { error in
                guard case .unsupportedScheme(let scheme)? = error as? PathUriParseError,
                      scheme == expectedScheme else {
                    XCTFail("expected UnsupportedScheme(\(expectedScheme)), got \(error)")
                    return
                }
            }
        }
    }

    func testPathUriSerializesAsAString() throws {
        let uri = try PathUri.parse("file:///workspace/src/lib.rs")
        // serde_json never escapes `/`; Foundation does unless told not to.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let data = try encoder.encode(uri)
        let json = String(decoding: data, as: UTF8.self)
        let deserialized = try JSONDecoder().decode(PathUri.self, from: data)
        XCTAssertEqual(json, "\"file:///workspace/src/lib.rs\"")
        XCTAssertEqual(deserialized, uri)
    }

    func testPathUriRejectsNativeAbsolutePathsDuringDeserialization() throws {
        let path = try AbsolutePathBuf.currentDir().join("workspace/src")
        let data = try JSONEncoder().encode(path)
        XCTAssertThrowsError(try JSONDecoder().decode(PathUri.self, from: data))
    }

    func testPathUriRejectsRelativeNativePaths() {
        XCTAssertThrowsError(try PathUri.fromHostNativePath("src/lib.rs")) { error in
            XCTAssertEqual((error as? IOError)?.kind, .invalidInput)
        }
    }

    func testPathUriRejectsRelativeStringsDuringDeserialization() {
        let data = Data("\"src/lib.rs\"".utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(PathUri.self, from: data)) { error in
            XCTAssertTrue(
                String(describing: error).contains("relative URL without a base"),
                "\(error)"
            )
        }
    }

    func testUnsupportedSchemeIsRejectedDuringDeserialization() {
        let data = Data("\"artifact://store/object-1\"".utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(PathUri.self, from: data)) { error in
            XCTAssertTrue(
                String(describing: error).contains("unsupported path URI scheme `artifact`"),
                "\(error)"
            )
        }
    }

    func testKnownPathUrisRejectQueriesAndFragments() {
        XCTAssertThrowsError(try PathUri.parse("file:///tmp/file.rs?version=1")) { error in
            XCTAssertEqual(error as? PathUriParseError, .queryNotAllowed)
        }
        XCTAssertThrowsError(try PathUri.parse("file:///tmp/file.rs#L1")) { error in
            XCTAssertEqual(error as? PathUriParseError, .fragmentNotAllowed)
        }
    }

    func testPathUrisRejectEncodedNullBytes() {
        XCTAssertThrowsError(try PathUri.parse("file:///tmp/%00"))
    }

    func testEncodedFilenameCharactersRoundTripWithoutBecomingUriMetadata() throws {
        let uri = try PathUri.parse("file:///tmp/a%3Fb%23c%25d")
        XCTAssertEqual(uri.description, "file:///tmp/a%3Fb%23c%25d")
        XCTAssertEqual(uri.encodedPath(), "/tmp/a%3Fb%23c%25d")
        XCTAssertEqual(uri.basename(), "a?b#c%d")
    }

    func testDoubleEncodedSeparatorRemainsFilenameText() throws {
        let uri = try PathUri.parse("file:///tmp/a%252Fb")
        XCTAssertEqual(uri.description, "file:///tmp/a%252Fb")
        XCTAssertEqual(uri.encodedPath(), "/tmp/a%252Fb")
        XCTAssertEqual(uri.basename(), "a%2Fb")
    }

    func testBasenameUsesDecodedUriSegments() throws {
        for (input, expected) in [
            ("file:///", String?.none),
            ("file:///workspace/src/lib.rs", .some("lib.rs")),
            ("file:///workspace/a%20file.rs", .some("a file.rs")),
            ("file:///C:/", .some("C:")),
            ("file://server/share", .some("share")),
        ] {
            let uri = try PathUri.parse(input)
            XCTAssertEqual(uri.basename(), expected, "basename for \(input)")
        }
    }

    func testPathBufUsesTheInferredNativeSpelling() throws {
        let windows = try PathUri.parse("file:///C:/Program%20Files/pwsh.exe")
        let posix = try PathUri.parse("file:///usr/local/bin/bash")
        XCTAssertEqual(windows.toPathBuf(), #"C:\Program Files\pwsh.exe"#)
        XCTAssertEqual(posix.toPathBuf(), "/usr/local/bin/bash")
    }

    func testParentStopsAtPosixDriveAndUncRoots() throws {
        for (input, expected) in [
            ("file:///workspace/src/lib.rs", String?.some("file:///workspace/src")),
            ("file:///workspace", .some("file:///")),
            ("file:///", nil),
            ("file:///C:/Users", .some("file:///C:")),
            ("file:///C:/", nil),
            ("file:///C:", nil),
            ("file://server/share/src/main.rs", .some("file://server/share/src")),
            ("file://server/share", nil),
        ] {
            let uri = try PathUri.parse(input)
            let expectedUri = try expected.map { try PathUri.parse($0) }
            XCTAssertEqual(uri.parent(), expectedUri, "parent for \(input)")
        }
    }

    func testAncestorsIncludeSelfAndStopAtNativePathRoots() throws {
        for (input, expected) in [
            ("file:///workspace/src", ["file:///workspace/src", "file:///workspace", "file:///"]),
            (
                "file:///C:/workspace/src",
                ["file:///C:/workspace/src", "file:///C:/workspace", "file:///C:"]
            ),
            (
                "file://server/share/project",
                ["file://server/share/project", "file://server/share"]
            ),
        ] {
            let uri = try PathUri.parse(input)
            XCTAssertEqual(uri.ancestors().map { $0.description }, expected, "ancestors for \(input)")
        }
    }

    func testJoinNormalizesRelativeUriSegments() throws {
        for (base, relative, expected) in [
            ("file:///workspace/src", "../tests/test.rs", "file:///workspace/tests/test.rs"),
            ("file:///", "../../etc", "file:///etc"),
            ("file:///C:/Users", "../Windows", "file:///C:/Windows"),
            ("file://server/share/src", "../tests", "file://server/share/tests"),
            ("file:///workspace", "a?b#c%d", "file:///workspace/a%3Fb%23c%25d"),
            ("file:///workspace/", "", "file:///workspace/"),
        ] {
            let baseUri = try PathUri.parse(base)
            let expectedUri = try PathUri.parse(expected)
            try XCTAssertEqual(try baseUri.join(relative), expectedUri, "joining \(relative)")
        }
    }

    func testJoinDescendantUsesTheBasePathConvention() throws {
        for (base, relative, expected) in [
            ("file:///workspace", "docs/../public", "file:///workspace/public"),
            ("file:///C:/workspace", #"docs\..\public"#, "file:///C:/workspace/public"),
            (
                "file://server/share/workspace",
                #"docs\..\public"#,
                "file://server/share/workspace/public"
            ),
        ] {
            let baseUri = try PathUri.parse(base)
            let expectedUri = try PathUri.parse(expected)
            try XCTAssertEqual(try baseUri.joinDescendant(relative), expectedUri, "joining \(relative)")
        }
    }

    func testJoinDescendantRejectsNonDescendantPaths() throws {
        for (base, path) in [
            ("file:///workspace", "/workspace/docs"),
            ("file:///workspace", "../outside"),
            ("file:///C:/workspace", #"\workspace\docs"#),
            ("file:///C:/workspace", #"C:\workspace\docs"#),
            ("file:///C:/workspace", #"C:docs"#),
            ("file:///C:/workspace", #"docs\file:stream"#),
            ("file://server/share/workspace", #"..\outside"#),
        ] {
            let baseUri = try PathUri.parse(base)
            XCTAssertThrowsError(try baseUri.joinDescendant(path), "joining \(path)") { error in
                XCTAssertEqual(
                    error as? PathUriParseError,
                    .joinPathMustBeDescendant(path),
                    "joining \(path)"
                )
            }
        }
    }

    func testJoinReplacesPosixAbsolutePath() throws {
        let base = try PathUri.parse("file:///workspace")
        try XCTAssertEqual(try base.join("/src"), try PathUri.parse("file:///src"))
    }

    func testJoinKeepsCanonicalizedPosixDoubleSlashPathsHierarchical() throws {
        let base = try PathUri.parse("file:///workspace")
        let cwd = try base.join("//server/share/project")
        try XCTAssertEqual(cwd, try PathUri.parse("file:///server/share/project"))
        try XCTAssertEqual(cwd.parent(), try PathUri.parse("file:///server/share"))
        try XCTAssertEqual(try cwd.join("AGENTS.md"), try PathUri.parse("file:///server/share/project/AGENTS.md"))
        // `#[cfg(unix)]` upstream.
        try XCTAssertEqual(
            try cwd.toAbsPath(),
            try AbsolutePathBuf.fromAbsolutePathChecked("/server/share/project")
        )
    }

    func testJoinNormalizesAbsoluteParentSegments() throws {
        for (base, path, expected) in [
            ("file:///workspace", "/tmp/a/../b", "file:///tmp/b"),
            ("file:///C:/workspace", #"D:\tmp\a\..\b"#, "file:///D:/tmp/b"),
            ("file:///C:/workspace", #"\\server\share\a\..\b"#, "file://server/share/b"),
            ("file:///C:/workspace", #"\\?\D:\reports\report.pdf"#, "file:///D:/reports/report.pdf"),
            ("file:///C:/workspace", #"\\.\D:\reports\report.pdf"#, "file:///D:/reports/report.pdf"),
            (
                "file:///C:/workspace",
                #"\\?\UNC\server\share\reports\report.pdf"#,
                "file://server/share/reports/report.pdf"
            ),
            (
                "file:///C:/workspace",
                #"\\.\UNC\server\share\reports\report.pdf"#,
                "file://server/share/reports/report.pdf"
            ),
            ("file:///workspace", "/tmp//a/../b", "file:///tmp/b"),
            ("file:///workspace", "/tmp/a/..//b", "file:///tmp/b"),
            ("file:///workspace", "/tmp/a///../b", "file:///tmp/b"),
            ("file:///C:/workspace", #"D:\tmp\a\\\..\b"#, "file:///D:/tmp/b"),
            ("file:///C:/workspace", #"\\server\share\a\\\..\b"#, "file://server/share/b"),
            ("file:///workspace", "/tmp/a///b/../..", "file:///tmp"),
            ("file:///C:/workspace", #"D:\tmp\a\\\b\..\.."#, "file:///D:/tmp"),
            ("file:///C:/workspace", #"\\server\share\a\\\b\..\.."#, "file://server/share"),
        ] {
            let baseUri = try PathUri.parse(base)
            let expectedUri = try PathUri.parse(expected)
            if normalizeWindowsDevicePath(path) != nil {
                try XCTAssertEqual(
                    try LegacyAppPathString.fromString(path).toPathUri(.windows),
                    expectedUri,
                    "converting \(path)"
                )
            }
            try XCTAssertEqual(try baseUri.join(path), expectedUri, "joining \(path)")
        }
    }

    func testWindowsNamespaceNormalizationPreservesOpaquePaths() throws {
        let base = try PathUri.parse("file:///C:/workspace")
        for path in [
            #"\\?\UNC\server"#,
            #"\\.\UNC\server"#,
            #"\\?\UNC\localhost\share\report.pdf"#,
            #"\\.\UNC\LOCALHOST\share\report.pdf"#,
            #"\\?\UNC\.\share\report.pdf"#,
            #"\\.\UNC\..\share\report.pdf"#,
            #"\\?\UNC\server\.\report.pdf"#,
            #"\\.\UNC\server\..\report.pdf"#,
            #"\\?\UNC\?\UNC\?\C:\report.pdf"#,
            #"\\.\UNC\?\UNC\?\C:\report.pdf"#,
            #"\\.\COM1"#,
            #"\\?\Volume{00000000-0000-0000-0000-000000000000}\report.pdf"#,
        ] {
            let expected = windowsOpaquePathUri(path)
            XCTAssertEqual(
                PathUri.fromAbsoluteNativePath(path, convention: .windows),
                expected,
                "parsing \(path)"
            )
            try XCTAssertEqual(
                try LegacyAppPathString.fromString(path).toPathUri(.windows),
                expected,
                "converting \(path)"
            )
            try XCTAssertEqual(try base.join(path), expected, "joining \(path)")
        }
    }

    func testJoinAbsoluteParentSegmentsStopAtNativePathRoots() throws {
        for (base, path, expected) in [
            ("file:///workspace", "/a/..", "file:///"),
            ("file:///C:/workspace", #"D:\a\.."#, "file:///D:/"),
            ("file:///C:/workspace", #"\\server\share\a\.."#, "file://server/share"),
            ("file:///workspace", "/../../b", "file:///b"),
            ("file:///C:/workspace", #"D:\..\..\b"#, "file:///D:/b"),
            ("file:///C:/workspace", #"\\server\share\..\..\b"#, "file://server/share/b"),
            ("file:///C:/workspace", #"\\server\share\\\..\b"#, "file://server/share/b"),
        ] {
            let baseUri = try PathUri.parse(base)
            let expectedUri = try PathUri.parse(expected)
            try XCTAssertEqual(try baseUri.join(path), expectedUri, "joining \(path)")
        }
    }

    func testJoinCollapsesRedundantAbsoluteSeparators() throws {
        for (base, path, expected) in [
            ("file:///workspace", "/tmp///", "file:///tmp/"),
            ("file:///workspace", "///", "file:///"),
            ("file:///workspace", "///server/share///", "file:///server/share/"),
            ("file:///C:/workspace", #"D:\tmp\\\"#, "file:///D:/tmp/"),
            ("file:///C:/workspace", #"D:\\\"#, "file:///D:/"),
            ("file:///C:/workspace", #"\\server\share\tmp\\\"#, "file://server/share/tmp/"),
            ("file:///C:/workspace", #"\\server\share\\\"#, "file://server/share/"),
        ] {
            let baseUri = try PathUri.parse(base)
            let expectedUri = try PathUri.parse(expected)
            try XCTAssertEqual(try baseUri.join(path), expectedUri, "joining \(path)")
        }
    }

    func testJoinReplacesWindowsAbsolutePath() throws {
        let base = try PathUri.parse("file:///C:/workspace/src")
        try XCTAssertEqual(try base.join(#"D:\tmp\test.rs"#), try PathUri.parse("file:///D:/tmp/test.rs"))
    }

    func testJoinWindowsRootRelativePathPreservesDriveOrShare() throws {
        for (base, path, expected) in [
            ("file:///C:/base/dir", #"\Windows"#, "file:///C:/Windows"),
            ("file://server/share/base/dir", #"\Windows"#, "file://server/share/Windows"),
        ] {
            let baseUri = try PathUri.parse(base)
            let expectedUri = try PathUri.parse(expected)
            try XCTAssertEqual(try baseUri.join(path), expectedUri, "joining \(path)")
        }
    }

    func testJoinResolvesWindowsSameDriveRelativePath() throws {
        for (base, path, expected) in [
            ("file:///C:/base", #"C:tmp"#, "file:///C:/base/tmp"),
            ("file:///C:/base", #"c:tmp"#, "file:///C:/base/tmp"),
            ("file:///C%3A/base", #"C:tmp"#, "file:///C%3A/base/tmp"),
            ("file:///C%3a/base", #"c:tmp"#, "file:///C%3a/base/tmp"),
            ("file:///C:/base/dir", #"C:..\tmp"#, "file:///C:/base/tmp"),
            ("file:///C:/base", "C:", "file:///C:/base"),
        ] {
            let baseUri = try PathUri.parse(base)
            let expectedUri = try PathUri.parse(expected)
            try XCTAssertEqual(try baseUri.join(path), expectedUri, "joining \(path)")
        }
    }

    func testJoinRejectsWindowsOtherDriveRelativePath() throws {
        let base = try PathUri.parse("file:///C:/base")
        XCTAssertThrowsError(try base.join(#"D:tmp"#)) { error in
            XCTAssertEqual(error as? PathUriParseError, .invalidFileUriPath(path: #"D:tmp"#))
        }
    }

    func testJoinParentSegmentsPreserveWindowsDriveOrShareAnchor() throws {
        for (base, expected) in [
            ("file:///C:/base/dir", "file:///C:/Windows"),
            ("file://server/share/base/dir", "file://server/share/Windows"),
        ] {
            let baseUri = try PathUri.parse(base)
            let expectedUri = try PathUri.parse(expected)
            try XCTAssertEqual(try baseUri.join(#"..\..\..\Windows"#), expectedUri)
        }
    }

    func testJoinRejectsNullPaths() throws {
        let base = try PathUri.parse("file:///workspace")
        XCTAssertThrowsError(try base.join("src\0file")) { error in
            XCTAssertEqual(error as? PathUriParseError, .invalidFileUriPath(path: "src\0file"))
        }
    }

    func testJoinUsesTheBaseUriPathConvention() throws {
        for (base, path, expected) in [
            ("file:///workspace/src", "../tests/test.rs", "file:///workspace/tests/test.rs"),
            ("file:///C:/workspace/src", #"..\tests\test.rs"#, "file:///C:/workspace/tests/test.rs"),
        ] {
            let baseUri = try PathUri.parse(base)
            let expectedUri = try PathUri.parse(expected)
            try XCTAssertEqual(try baseUri.join(path), expectedUri, "joining \(path)")
        }
    }

    func testStartsWithUsesUriSegmentBoundaries() throws {
        for (path, base, expected) in [
            ("file:///workspace/plugin", "file:///", true),
            ("file:///workspace/plugin", "file:///workspace/plugin", true),
            ("file:///workspace/plugin/assets/icon.svg", "file:///workspace/plugin", true),
            ("file:///workspace/plugin-other/icon.svg", "file:///workspace/plugin", false),
            ("file:///C:/plugins/foo/assets/icon.svg", "file:///C:/plugins/foo", true),
            ("file:///C:/project/secret", "file:///%63%3A/project", false),
            ("file:///C:/PLUGINS/%C3%84/assets/icon.svg", "file:///c:/plugins/%C3%A4", false),
            ("file:///C:/plugins/ǈ/assets/icon.svg", "file:///C:/plugins/Ǉ", false),
            ("file:///C:/plugins/foo2/assets/icon.svg", "file:///C:/plugins/foo", false),
            ("file://server/share/plugins/foo/icon.svg", "file://server/share/plugins/foo", true),
            ("file://SERVER/SHARE/PLUGINS/FOO/icon.svg", "file://server/share/plugins/foo", true),
            ("file:///WORKSPACE/plugin", "file:///workspace", false),
            ("file://other/share/plugins/foo/icon.svg", "file://server/share/plugins/foo", false),
            ("file:///workspace/plugin/%2F..%2Foutside", "file:///workspace/plugin", false),
            ("file:///workspace/pri%76ate/file", "file:///workspace/%70rivate", true),
            ("file:///workspace/%ff/file", "file:///workspace/%FF", true),
            ("file:///workspace/plugin/%5C..%5Coutside", "file:///workspace/plugin", true),
            ("file:///C:/plugins/foo/%5C..%5Coutside", "file:///C:/plugins/foo", false),
        ] {
            let pathUri = try PathUri.parse(path)
            let baseUri = try PathUri.parse(base)
            XCTAssertEqual(pathUri.startsWith(baseUri), expected, "\(path) vs \(base)")
        }
    }

    func testOverlapsUsesLexicalContainment() throws {
        for (left, right, expected) in [
            ("file:///workspace", "file:///workspace/src", Bool?.some(true)),
            ("file:///C:/WORKSPACE", "file:///c:/workspace/src", .some(true)),
            ("file:///workspace/src", "file:///workspace/tests", .some(false)),
            ("file:///WORKSPACE", "file:///workspace/src", .some(false)),
        ] {
            let leftUri = try PathUri.parse(left)
            let rightUri = try PathUri.parse(right)
            XCTAssertEqual(leftUri.overlaps(rightUri), expected, "\(left) and \(right)")
            XCTAssertEqual(rightUri.overlaps(leftUri), expected, "\(right) and \(left)")
        }

        let opaque = PathUri.fromOpaquePathBytes([UInt8]("/workspace/private".utf8))
        let lexical = try PathUri.parse("file:///workspace")
        XCTAssertEqual(opaque.overlaps(opaque), true)
        XCTAssertNil(opaque.overlaps(lexical))
        XCTAssertNil(lexical.overlaps(opaque))
    }

    func testLexicalDepthCountsValidatedNonemptySegments() throws {
        for (path, expected) in [
            ("file:///", Int?.some(0)),
            ("file:///workspace////", .some(1)),
            ("file:///workspace/%70rivate", .some(2)),
            ("file:///workspace/private%2Fsecret", nil),
        ] {
            let pathUri = try PathUri.parse(path)
            XCTAssertEqual(pathUri.lexicalDepth(), expected, "lexical depth for \(path)")
        }
        XCTAssertNil(PathUri.fromOpaquePathBytes([UInt8]("/workspace".utf8)).lexicalDepth())
    }

    func testToUrlReturnsTheValidatedUrl() throws {
        let uri = try PathUri.parse("file://localhost/workspace/a%20file.rs")
        try XCTAssertEqual(uri.toUrl(), try FileUrl.parse("file:///workspace/a%20file.rs"))
    }
}
