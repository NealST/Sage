//
//  response_item_id.swift
//  SageTests
//
//  Port of codex-rs/protocol/src/response_item_id_tests.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//

import Foundation
import XCTest
@testable import CodexProtocol

final class ResponseItemIdTests: XCTestCase {
    func testCreatesPrefixedUuidV7Ids() throws {
        let id = ResponseItemId(new: "msg")
        let suffix = try XCTUnwrap(id.asStr.split(separator: "_").last.map(String.init))
        XCTAssertTrue(id.asStr.hasPrefix("msg_"))
        // uuid::Version::SortRand == v7: version nibble at index 14.
        let hex = suffix.replacingOccurrences(of: "-", with: "")
        XCTAssertEqual(hex.count, 32)
        XCTAssertEqual(hex[hex.index(hex.startIndex, offsetBy: 12)], "7")
    }

    func testCreatesPrefixedIdsWithExplicitSuffix() {
        let id = ResponseItemId(withSuffix: "msg", suffix: "test")
        XCTAssertEqual(id.asStr, "msg_test")
        XCTAssertEqual(id.description, "msg_test")
        XCTAssertEqual(id.string, "msg_test")
    }

    func testAcceptsServerIdsVerbatim() {
        let id = ResponseItemId.fromServer("legacy-id")
        XCTAssertEqual(id.asStr, "legacy-id")
    }

    func testDeserializesArbitraryIdsAsStrings() throws {
        let id = try JSONDecoder().decode(ResponseItemId.self, from: Data("\"legacy-id\"".utf8))
        XCTAssertEqual(id.asStr, "legacy-id")
        let data = try JSONEncoder().encode(id)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "\"legacy-id\"")
    }

    func testRecognizesNonEmptyPrefixAndSuffix() throws {
        for (value, expected) in [
            ("msg_test", true),
            ("legacy-id", false),
            ("", false),
            ("_test", false),
            ("msg_", false),
        ] {
            let data = Data("\"\(value)\"".utf8)
            let id = try JSONDecoder().decode(ResponseItemId.self, from: data)
            XCTAssertEqual(id.isPrefixed, expected, value)
        }
    }
}
