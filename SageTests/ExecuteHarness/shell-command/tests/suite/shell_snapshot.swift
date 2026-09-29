//
//  shell_snapshot.swift
//  SageTests
//
//  Port of selected cases from
//  codex-rs/shell-command/src/shell_snapshot_tests.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

@testable import CodexShellCommand
import XCTest

final class ShellCommandSnapshotTests: XCTestCase {
    func testLooksLikeCredentialName() {
        XCTAssertTrue(looksLikeCredentialName("VENDOR_PASSWORD"))
        XCTAssertTrue(looksLikeCredentialName("api_token"))
        XCTAssertFalse(looksLikeCredentialName("PATH"))
        XCTAssertFalse(looksLikeCredentialName("HOME"))
    }

    func testSnapshotLiteralWordsPlainCommand() {
        let words = snapshotLiteralWords("echo hello world\n", shellType: .bash)
        XCTAssertEqual(words, ["echo", "hello", "world"])
    }

    func testSnapshotLiteralWordsAnsiC() {
        let words = snapshotLiteralWords(#"printf $'a\nb'"# + "\n", shellType: .bash)
        XCTAssertEqual(words, ["printf", "a\nb"])
    }

    func testCapturedSnapshotRequiresMarkerAndCompleteRecords() {
        for captured in [
            "missing header\0\0\0",
            "# Snapshot file\n\0",
            "# Snapshot file\n\0\0NAME\0export NAME=value\n",
        ] {
            XCTAssertNil(
                CapturedSnapshot.parse(shellType: .bash, captured: Array(captured.utf8)),
                captured
            )
        }
    }

    func testCapturedSnapshotParsePlainExports() {
        var bytes = [UInt8]()
        func appendRecord(_ text: String) {
            bytes.append(contentsOf: text.utf8)
            bytes.append(0)
        }
        appendRecord("# Snapshot file\n# Functions\n")
        appendRecord("# aliases 0\n")
        appendRecord("PATH")
        appendRecord("export PATH=/usr/bin\n")
        appendRecord("")
        bytes.append(contentsOf: "PATH=/usr/bin".utf8)

        let snapshot = CapturedSnapshot.parse(shellType: .bash, captured: bytes)
        XCTAssertEqual(snapshot?.exports.count, 1)
        XCTAssertEqual(snapshot?.exports.first?.key, "PATH")
        XCTAssertEqual(snapshot?.exports.first?.value, .plain)
    }

    func testZshTiedArrayDecodesLiteralElements() {
        let first = "abcdefghij"
        let last = "klmnopqrst"
        let data = "# Snapshot file\n\0\0AUTH_HEADER\0typeset -xT AUTH_HEADER header=( '\(first)' '\(last)' ) ''\n\0\0"
        let snapshot = CapturedSnapshot.parse(shellType: .zsh, captured: Array(data.utf8))
        XCTAssertNotNil(snapshot)
        guard let export = snapshot?.exports.first else {
            return XCTFail("expected AUTH_HEADER export")
        }
        XCTAssertEqual(export.key, "AUTH_HEADER")
        guard case .tiedArray(let array) = export.value else {
            return XCTFail("expected tied array, got \(export.value)")
        }
        XCTAssertEqual(array.values.map { String(decoding: $0, as: UTF8.self) }, [first, last])
    }

    func testPrepareSnapshotCredentialsRejectsCrossingArrayElements() {
        let real = "password$abcdefghijklmno"
        let dummy = "dummy-0123456789abcdef"
        let keys = ["VENDOR_PASSWORD"]
        let restored = [keys[0]: real]
        for (capturedValue, allowedValue) in [(real, dummy), (real, real), (dummy, dummy)] {
            let original = [
                keys[0]: capturedValue,
                "AUTH_HEADER": capturedValue,
            ]
            let allowed = [
                keys[0]: allowedValue,
                "AUTH_HEADER": allowedValue,
            ]
            let mid = capturedValue.index(capturedValue.startIndex, offsetBy: 10)
            let first = String(capturedValue[..<mid])
            let last = String(capturedValue[mid...])
            let data = "# Snapshot file\n\0\0AUTH_HEADER\0typeset -xT AUTH_HEADER header=( '\(first)' '\(last)' ) ''\n\0\0"
            guard let capture = CapturedSnapshot.parse(shellType: .zsh, captured: Array(data.utf8)) else {
                XCTFail("parse failed for \(capturedValue)")
                continue
            }
            let prepared = prepareSnapshotCredentials(
                captured: capture,
                environment: SnapshotCredentialEnvironment(
                    original: original,
                    restored: restored,
                    configured: [:],
                    discovered: allowed,
                    allowed: allowed,
                    isAllowedUnset: { _ in true },
                    brokeredKeys: keys,
                    brokeredAliasKeys: [],
                    allowedBrokeredKeys: keys
                )
            ) { text in
                text = text.replacingOccurrences(of: real, with: allowedValue)
                return true
            }
            XCTAssertNil(prepared, "\(capturedValue), \(allowedValue)")
        }
    }

    func testPrepareSnapshotCredentialsPassesPlainAllowedExport() {
        var bytes = [UInt8]()
        func appendRecord(_ text: String) {
            bytes.append(contentsOf: text.utf8)
            bytes.append(0)
        }
        appendRecord("# Snapshot file\n")
        appendRecord("")
        appendRecord("APP_SETTING")
        appendRecord("export APP_SETTING=value\n")
        appendRecord("")
        guard let capture = CapturedSnapshot.parse(shellType: .bash, captured: bytes) else {
            return XCTFail("parse failed")
        }
        let prepared = prepareSnapshotCredentials(
            captured: capture,
            environment: SnapshotCredentialEnvironment(
                original: ["APP_SETTING": "value"],
                restored: [:],
                configured: [:],
                discovered: [:],
                allowed: ["APP_SETTING": "value"],
                isAllowedUnset: { _ in true },
                brokeredKeys: [],
                brokeredAliasKeys: [],
                allowedBrokeredKeys: []
            )
        ) { _ in true }
        XCTAssertEqual(prepared?.script.contains("export APP_SETTING=value"), true)
        XCTAssertEqual(prepared?.aliases.isEmpty, true)
        XCTAssertEqual(prepared?.rejectedAliasKeys.isEmpty, true)
    }
}
