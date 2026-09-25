//
//  turn_input.swift
//  SageTests
//
//  Port of focused cases from codex-rs/protocol/src/turn_input.rs
//  (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//

import Foundation
import XCTest
@testable import CodexProtocol

final class TurnInputTests: XCTestCase {
    func testCyberAccessProgramSnakeCase() throws {
        let encoded = String(
            decoding: try JSONEncoder().encode(CyberAccessProgram.daybreakBlue),
            as: UTF8.self)
        XCTAssertEqual(encoded, "\"daybreak_blue\"")
        XCTAssertEqual(
            try JSONDecoder().decode(CyberAccessProgram.self, from: Data(#""daybreak_red""#.utf8)),
            .daybreakRed)
        XCTAssertEqual(
            try JSONDecoder().decode(CyberAccessProgram.self, from: Data(#""standard""#.utf8)),
            .standard)
    }

    func testNotSubmittedReasonEquality() {
        XCTAssertEqual(NotSubmittedReason.notIdle, .notIdle)
        XCTAssertEqual(
            NotSubmittedReason.expectedTurnMismatch(expected: "a", actual: "b"),
            .expectedTurnMismatch(expected: "a", actual: "b"))
        XCTAssertNotEqual(
            NotSubmittedReason.expectedTurnMismatch(expected: "a", actual: "b"),
            .expectedTurnMismatch(expected: "a", actual: "c"))
        XCTAssertEqual(
            NotSubmittedReason.activeTurnNotSteerable(turnKind: .review),
            .activeTurnNotSteerable(turnKind: .review))
    }

    func testTurnInputRequestUserInputHelper() {
        let request = TurnInputRequest.userInput([.text(text: "hello", textElements: [])])
        if case .userInput(let content, let clientId) = request.input {
            XCTAssertEqual(content, [.text(text: "hello", textElements: [])])
            XCTAssertNil(clientId)
        } else {
            XCTFail("expected userInput")
        }
        XCTAssertTrue(request.threadSettings.isEmpty)
        XCTAssertNil(request.start.cyberAccessProgram)
        XCTAssertTrue(request.additionalContext.isEmpty)
    }
}
