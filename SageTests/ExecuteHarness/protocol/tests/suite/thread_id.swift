//
//  thread_id.swift
//  SageTests
//
//  Port of the inline `#[cfg(test)] mod tests` in
//  codex-rs/protocol/src/thread_id.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//
//  Plus wire-format checks for the string Codable contract and `from_u128`.
//

import Foundation
@testable import CodexProtocol
import XCTest

final class ThreadIdTests: XCTestCase {
    /// `test_thread_id_default_is_not_zeroes`
    func testThreadIdDefaultIsNotZeroes() {
        let id = ThreadId()
        XCTAssertNotEqual(id.description, "00000000-0000-0000-0000-000000000000")
    }

    func testFromU128RoundTrip() {
        // 0x00112233-4455-6677-8899-aabbccddeeff
        let value: UInt128 = 0x00112233445566778899AABBCCDDEEFF
        let id = ThreadId(u128: value)
        XCTAssertEqual(id.description, "00112233-4455-6677-8899-aabbccddeeff")
    }

    func testCodableEncodesAsPlainString() throws {
        let id = ThreadId()
        let data = try JSONEncoder().encode(id)
        XCTAssertEqual(String(data: data, encoding: .utf8), "\"\(id.description)\"")
        try XCTAssertEqual(JSONDecoder().decode(ThreadId.self, from: data), id)
    }

    func testRolloutIdIsThreadId() {
        let id = ThreadId()
        let rolloutId: RolloutId = id
        XCTAssertEqual(rolloutId, id)
    }
}
