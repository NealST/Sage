//
//  schema_loader.swift
//  SageTests
//
//  Port of selected cases from
//  codex-rs/hooks/src/engine/schema_loader.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

@testable import CodexHooks
import CodexProtocol
import XCTest

final class HooksSchemaLoaderTests: XCTestCase {
    func testLoadsGeneratedHookSchemas() {
        let schemas = generatedHookSchemas()
        XCTAssertEqual(schemaType(schemas.postToolUseCommandInput), "object")
        XCTAssertEqual(schemaType(schemas.postToolUseCommandOutput), "object")
        XCTAssertEqual(schemaType(schemas.permissionRequestCommandInput), "object")
        XCTAssertEqual(schemaType(schemas.permissionRequestCommandOutput), "object")
        XCTAssertEqual(schemaType(schemas.postCompactCommandInput), "object")
        XCTAssertEqual(schemaType(schemas.postCompactCommandOutput), "object")
        XCTAssertEqual(schemaType(schemas.preToolUseCommandInput), "object")
        XCTAssertEqual(schemaType(schemas.preToolUseCommandOutput), "object")
        XCTAssertEqual(schemaType(schemas.preCompactCommandInput), "object")
        XCTAssertEqual(schemaType(schemas.preCompactCommandOutput), "object")
        XCTAssertEqual(schemaType(schemas.sessionStartCommandInput), "object")
        XCTAssertEqual(schemaType(schemas.sessionStartCommandOutput), "object")
        XCTAssertEqual(schemaType(schemas.sessionEndCommandInput), "object")
        XCTAssertEqual(schemaType(schemas.subagentStartCommandInput), "object")
        XCTAssertEqual(schemaType(schemas.subagentStartCommandOutput), "object")
        XCTAssertEqual(schemaType(schemas.subagentStopCommandInput), "object")
        XCTAssertEqual(schemaType(schemas.subagentStopCommandOutput), "object")
        XCTAssertEqual(schemaType(schemas.userPromptSubmitCommandInput), "object")
        XCTAssertEqual(schemaType(schemas.userPromptSubmitCommandOutput), "object")
        XCTAssertEqual(schemaType(schemas.stopCommandInput), "object")
        XCTAssertEqual(schemaType(schemas.stopCommandOutput), "object")
        XCTAssertEqual(schemaType(schemas.interruptCommandInput), "object")
        XCTAssertEqual(schemaType(schemas.interruptCommandOutput), "object")
    }
}

private func schemaType(_ value: JSONValue) -> String? {
    value.objectValue?["type"]?.stringValue
}
