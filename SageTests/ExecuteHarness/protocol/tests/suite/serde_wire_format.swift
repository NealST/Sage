//
//  serde_wire_format.swift
//  SageTests
//
//  Sage addition (no codex counterpart).
//
//  Wire-format guards for the hand-rolled serde semantics in this module:
//  tagged/untagged enums, deny_unknown_fields, BTreeMap sorted keys,
//  explicit-null vs skip_serializing_if, and RFC 3339 timestamps.
//

import Foundation
import XCTest
@testable import CodexProtocol

final class SerdeWireFormatTests: XCTestCase {
    // MARK: - ParsedCommand (tagged "type")

    func testParsedCommandTaggedRoundTrip() throws {
        let json = #"{"type":"search","cmd":"rg foo","query":"foo","path":null}"#
        let command = try JSONDecoder().decode(ParsedCommand.self, from: Data(json.utf8))
        XCTAssertEqual(command, .search(cmd: "rg foo", query: "foo", path: nil))
        // No skip_serializing_if: None encodes as explicit null.
        let encoded = String(decoding: try JSONEncoder().encode(command), as: UTF8.self)
        XCTAssertTrue(encoded.contains("\"path\":null"), encoded)
    }

    func testParsedCommandSnakeCaseVariant() throws {
        let json = #"{"type":"list_files","cmd":"ls"}"#
        let command = try JSONDecoder().decode(ParsedCommand.self, from: Data(json.utf8))
        XCTAssertEqual(command, .listFiles(cmd: "ls", path: nil))
        let encoded = String(decoding: try JSONEncoder().encode(command), as: UTF8.self)
        XCTAssertTrue(encoded.contains("\"type\":\"list_files\""), encoded)
    }

    // MARK: - UpdatePlanArgs (deny_unknown_fields, explicit null)

    func testUpdatePlanArgsRejectsUnknownFields() {
        let json = #"{"plan":[],"bogus":1}"#
        XCTAssertThrowsError(try JSONDecoder().decode(UpdatePlanArgs.self, from: Data(json.utf8)))
    }

    func testUpdatePlanArgsEncodesExplicitNullExplanation() throws {
        let args = UpdatePlanArgs(plan: [PlanItemArg(step: "s", status: .inProgress)])
        let encoded = String(decoding: try JSONEncoder().encode(args), as: UTF8.self)
        XCTAssertTrue(encoded.contains("\"explanation\":null"), encoded)
        XCTAssertTrue(encoded.contains("\"in_progress\""), encoded)
    }

    // MARK: - SecurityRiskScore (sorted keys, skip_serializing_if, RFC 3339)

    func testSecurityRiskScoreSortedKeysAndSkippedNils() throws {
        let score = SecurityRiskScore(scores: ["b": 2.0, "a": 1.0])
        // Foundation's JSONEncoder emits keys in unspecified order; compare
        // through JSONValue.encodedString() (serde_json semantics: BTreeMap
        // keys sorted, struct fields present unless skip_serializing_if).
        let value = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(score))
        XCTAssertEqual(value.encodedString(), #"{"scores":{"a":1,"b":2}}"#)
    }

    func testSecurityRiskScoreRfc3339() throws {
        let json = #"{"scores":{},"sampled_at":"2026-09-24T08:30:00.000Z"}"#
        let score = try JSONDecoder().decode(SecurityRiskScore.self, from: Data(json.utf8))
        let encoded = String(decoding: try JSONEncoder().encode(score), as: UTF8.self)
        XCTAssertTrue(encoded.contains("2026-09-24T08:30:00.000Z"), encoded)
    }

    // MARK: - McpServerRequirement (untagged fallback order)

    func testMcpServerRequirementExactIdentity() throws {
        let json = #"{"identity":{"command":"npx"}}"#
        let requirement = try JSONDecoder().decode(McpServerRequirement.self, from: Data(json.utf8))
        XCTAssertEqual(requirement, .identity(identity: .command(command: "npx")))
    }

    func testMcpServerRequirementMatcherForms() throws {
        let commandJson = #"{"identity":{"command":{"executable":"npx","args":[{"match":"exact","value":"-y"}]}}}"#
        let requirement = try JSONDecoder().decode(McpServerRequirement.self, from: Data(commandJson.utf8))
        XCTAssertEqual(
            requirement,
            .command(McpServerCommandMatcher(executable: "npx", args: [.exact(value: "-y")]))
        )

        let urlJson = #"{"identity":{"url":{"match":"prefix","value":"https://"}}}"#
        let urlRequirement = try JSONDecoder().decode(McpServerRequirement.self, from: Data(urlJson.utf8))
        XCTAssertEqual(urlRequirement, .url(.prefix(value: "https://")))
    }

    func testMcpServerMatcherRejectsUnknownFields() {
        // RawMcpServerCommandIdentity has deny_unknown_fields.
        let json = #"{"identity":{"command":{"executable":"npx","args":[]},"url":{"match":"exact","value":"x"}}}"#
        XCTAssertThrowsError(try JSONDecoder().decode(McpServerRequirement.self, from: Data(json.utf8)))
    }

    func testMcpServerValueMatcherUnknownVariant() {
        let json = #"{"match":"glob","value":"x"}"#
        XCTAssertThrowsError(try JSONDecoder().decode(McpServerValueMatcher.self, from: Data(json.utf8)))
    }
}
