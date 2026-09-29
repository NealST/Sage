//
//  protocol_events.swift
//  SageTests
//
//  Sage addition (no codex counterpart).
//
//  Guards for EventMsg variants and truncation helpers added while
//  finishing the protocol.swift / models.swift port.
//

import Foundation
import XCTest
@testable import CodexProtocol

final class ProtocolEventsTests: XCTestCase {
    func testWarningEventRoundTrip() throws {
        let event = EventMsg.warning(WarningEvent(message: "slow"))
        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(EventMsg.self, from: data)
        XCTAssertEqual(decoded, event)
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(json.contains("\"type\":\"warning\""), json)
    }

    func testTurnAbortedAndShutdownCompleteRoundTrip() throws {
        let aborted = EventMsg.turnAborted(TurnAbortedEvent(turnId: "t1", reason: .interrupted))
        XCTAssertEqual(
            try JSONDecoder().decode(EventMsg.self, from: JSONEncoder().encode(aborted)),
            aborted)

        let shutdown = EventMsg.shutdownComplete
        let encoded = String(decoding: try JSONEncoder().encode(shutdown), as: UTF8.self)
        XCTAssertTrue(encoded.contains("\"type\":\"shutdown_complete\""), encoded)
        XCTAssertEqual(
            try JSONDecoder().decode(EventMsg.self, from: Data(encoded.utf8)),
            .shutdownComplete)
    }

    func testTokenCountEventRoundTrip() throws {
        let event = EventMsg.tokenCount(TokenCountEvent(info: nil, rateLimits: nil))
        XCTAssertEqual(
            try JSONDecoder().decode(EventMsg.self, from: JSONEncoder().encode(event)),
            event)
    }

    func testTruncationPolicyBytesAndTokens() {
        let content = "example output"
        XCTAssertEqual(
            formattedTruncateText(content, policy: .tokens(10)),
            content)
        XCTAssertEqual(
            formattedTruncateText(content, policy: .bytes(20)),
            content)

        var payload = FunctionCallOutputPayload.fromText("abcdefghij")
        truncateFunctionOutputPayload(&payload, policy: .bytes(4)) { _ in 0 }
        XCTAssertNotEqual(payload.textContent, "abcdefghij")
        XCTAssertFalse(payload.textContent?.isEmpty ?? true)
    }

    func testThreadMemoryModeLowercase() throws {
        XCTAssertEqual(
            try JSONDecoder().decode(ThreadMemoryMode.self, from: Data(#""enabled""#.utf8)),
            .enabled)
        XCTAssertEqual(
            String(decoding: try JSONEncoder().encode(ThreadMemoryMode.disabled), as: UTF8.self),
            #""disabled""#)
    }

    func testResponseItemIdPrefixAndSetId() {
        var item = ResponseItem.message(
            id: nil, role: "user", content: [], phase: nil,
            internalChatMessageMetadataPassthrough: nil)
        XCTAssertEqual(item.idPrefix(), "msg")
        XCTAssertTrue(item.isUserMessage())
        item.setId(.fromServer("msg_1"))
        XCTAssertEqual(item.id()?.asStr, "msg_1")
        item.setTurnIdIfMissing("turn-1")
        XCTAssertEqual(item.turnId(), "turn-1")
        item.setTurnIdIfMissing("turn-2")
        XCTAssertEqual(item.turnId(), "turn-1")
    }
}
