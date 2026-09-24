//
//  session_id.swift
//  SageTests
//
//  Port of the inline `#[cfg(test)] mod tests` in
//  codex-rs/protocol/src/session_id.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//
//  Plus wire-format checks for the string Codable contract (serde
//  `collect_str` / string deserialize).
//

import Foundation
@testable import CodexProtocol
import XCTest

final class SessionIdTests: XCTestCase {
    /// `test_session_id_default_is_not_zeroes`
    func testSessionIdDefaultIsNotZeroes() {
        let id = SessionId()
        XCTAssertNotEqual(id.description, "00000000-0000-0000-0000-000000000000")
    }

    /// `converts_to_and_from_thread_id`
    func testConvertsToAndFromThreadId() {
        let threadId = ThreadId()
        let sessionId = SessionId(threadId)
        XCTAssertEqual(ThreadId(sessionId), threadId)
    }

    func testStringRoundTrip() throws {
        let id = SessionId()
        let parsed = try SessionId.fromString(id.description)
        XCTAssertEqual(parsed, id)
    }

    func testCodableEncodesAsPlainString() throws {
        let id = SessionId()
        let data = try JSONEncoder().encode(id)
        XCTAssertEqual(String(data: data, encoding: .utf8), "\"\(id.description)\"")
        try XCTAssertEqual(JSONDecoder().decode(SessionId.self, from: data), id)
    }

    func testInvalidStringThrows() {
        XCTAssertThrowsError(try SessionId.fromString("not-a-uuid")) { error in
            XCTAssertEqual(error as? InvalidUUIDError, .invalidString("not-a-uuid"))
        }
    }
}
