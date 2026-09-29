//
//  output_parser.swift
//  SageTests
//
//  Port of selected cases from
//  codex-rs/hooks/src/engine/output_parser.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

@testable import CodexHooks
import CodexProtocol
import CodexUtils
import XCTest

final class HooksOutputParserTests: XCTestCase {
    func testLooksLikeJSONUsesLeadingBrace() {
        XCTAssertTrue(looksLikeJSON("  {\"continue\":true}"))
        XCTAssertTrue(looksLikeJSON("[1]"))
        XCTAssertFalse(looksLikeJSON("ok"))
    }

    func testStructuredOutputRejectsInvalidShapesAndTypes() {
        for stdout in [
            "[]",
            #"{"systemMessage":123}"#,
            #"{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":123}}"#,
            #"{"hookSpecificOutput":{"additionalContext":"missing event name"}}"#,
            #"{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","updatedInput":{}}}"#,
            #"{"unexpectedField":true}"#,
            "{",
        ] {
            XCTAssertNil(parseUserPromptSubmit(stdout), stdout)
        }
    }

    func testPermissionRequestRejectsReservedUpdatedInputField() {
        let parsed = parsePermissionRequest(
            #"{"continue":true,"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow","updatedInput":{}}}}"#
        )
        XCTAssertEqual(
            parsed?.invalidReason,
            "PermissionRequest hook returned unsupported updatedInput"
        )
    }

    func testPermissionRequestRejectsReservedUpdatedPermissionsField() {
        let parsed = parsePermissionRequest(
            #"{"continue":true,"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow","updatedPermissions":{}}}}"#
        )
        XCTAssertEqual(
            parsed?.invalidReason,
            "PermissionRequest hook returned unsupported updatedPermissions"
        )
    }

    func testPermissionRequestRejectsReservedInterruptField() {
        let parsed = parsePermissionRequest(
            #"{"continue":true,"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow","interrupt":true}}}"#
        )
        XCTAssertEqual(
            parsed?.invalidReason,
            "PermissionRequest hook returned unsupported interrupt:true"
        )
    }

    func testPermissionRequestAllowPasses() {
        let parsed = parsePermissionRequest(
            #"{"continue":true,"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}"#
        )
        XCTAssertEqual(parsed?.decision, .allow)
        XCTAssertNil(parsed?.invalidReason)
    }

    func testPreToolUseDenyRequiresReason() {
        let missing = parsePreToolUse(
            #"{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny"}}"#
        )
        XCTAssertEqual(
            missing?.invalidReason,
            "PreToolUse hook returned permissionDecision:deny without a non-empty permissionDecisionReason"
        )
        let blocked = parsePreToolUse(
            #"{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"no"}}"#
        )
        XCTAssertEqual(blocked?.blockReason, "no")
        XCTAssertNil(blocked?.invalidReason)
    }

    func testPostToolUseBlockRequiresReason() {
        let parsed = parsePostToolUse(#"{"decision":"block"}"#)
        XCTAssertEqual(
            parsed?.invalidBlockReason,
            "PostToolUse hook returned decision:block without a non-empty reason"
        )
        XCTAssertEqual(parsed?.shouldBlock, false)
    }

    func testInterruptReadsSystemMessage() {
        let parsed = parseInterrupt(#"{"systemMessage":"stopped"}"#)
        XCTAssertEqual(parsed?.systemMessage, "stopped")
    }

    func testCommandInputUsesRequestToolName() throws {
        let request = PreToolUseRequest(
            sessionId: ThreadId(),
            turnId: "turn-1",
            cwd: try AbsolutePathBuf.fromAbsolutePath("/tmp"),
            model: "gpt",
            permissionMode: "default",
            toolName: "shell",
            toolUseId: "call-1",
            toolInput: .object(["command": .string("ls")])
        )
        let json = commandInputJSON(request)
        XCTAssertTrue(json.contains("\"tool_name\":\"shell\""), json)
        XCTAssertTrue(json.contains("\"hook_event_name\":\"PreToolUse\""), json)
        XCTAssertFalse(json.contains("agent_id"), json)
    }
}
