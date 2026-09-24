//
//  json_tests.swift
//  SageTests
//
//  Port of codex-rs/utils/string/src/json.rs #[cfg(test)] (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  The upstream test payload uses hand-rolled `Serialize` impls with a
//  single-entry `BTreeMap`; the port uses `Encodable` structs (declaration
//  order = emission order) with a single-entry `Dictionary`.
//  `serde_json::from_str::<Value>` maps to `JSONSerialization` + `NSDictionary`
//  equality.
//

import Foundation
import XCTest
@testable import CodexUtils

final class JsonStringTests: XCTestCase {

    private struct TestPayload: Encodable {
        let workspaces: [String: TestWorkspace]
    }

    private struct TestWorkspace: Encodable {
        let label: String
        let emoji: String
    }

    /// `to_ascii_json_string_escapes_non_ascii_strings`.
    func testToAsciiJsonStringEscapesNonAsciiStrings() throws {
        let value = TestPayload(workspaces: [
            "/tmp/東京": TestWorkspace(label: "Agentlarım", emoji: "🚀"),
        ])

        let serialized = try toAsciiJsonString(value)

        XCTAssertEqual(
            serialized,
            #"{"workspaces":{"/tmp/東京":{"label":"Agentlar\u0131m","emoji":"\ud83d\ude80"}}}"#
        )
        XCTAssertTrue(serialized.allSatisfy(\.isASCII))
        XCTAssertFalse(serialized.contains("東京"))
        XCTAssertFalse(serialized.contains("Agentlarım"))
        XCTAssertFalse(serialized.contains("🚀"))
        let parsed = try JSONSerialization.jsonObject(with: Data(serialized.utf8))
        XCTAssertEqual(
            parsed as? NSDictionary,
            ["workspaces": ["/tmp/東京": ["label": "Agentlarım", "emoji": "🚀"]]] as NSDictionary
        )
    }

    /// `bounded_json_counts_utf8_output_bytes`.
    func testBoundedJsonCountsUtf8OutputBytes() throws {
        // The shim's `XCTAssertEqual` is `rethrows`: a throwing argument
        // makes the whole call throwing.
        try XCTAssertEqual(try toJsonStringBounded("é", maxBytes: 4), #""é""#)
        XCTAssertThrowsError(try toJsonStringBounded("é", maxBytes: 3))
        XCTAssertThrowsError(try toJsonStringBounded(
            String(repeating: "a", count: 100_000),
            maxBytes: 16 * 1024
        ))
    }
}
