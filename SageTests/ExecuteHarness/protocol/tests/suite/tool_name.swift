//
//  tool_name.swift
//  SageTests
//
//  Sage addition (no codex counterpart) — codex-rs/protocol/src/tool_name.rs
//  has no inline tests; these pin the ported semantics (default namespace,
//  Display join, Option-aware ordering, explicit-null Codable).
//

import Foundation
@testable import CodexProtocol
import XCTest

final class ToolNameTests: XCTestCase {
    func testPlainHasNoNamespace() {
        let name = ToolName(plain: "shell")
        XCTAssertTrue(name.isDefaultNamespace())
        XCTAssertEqual(name.description, "shell")
    }

    func testDefaultNamespaceDisplaysPlain() {
        let name = ToolName(namespaced: "functions", name: "shell")
        XCTAssertTrue(name.isDefaultNamespace())
        XCTAssertEqual(name.description, "shell")
    }

    func testCustomNamespaceJoinsWithoutSeparator() {
        let name = ToolName(namespaced: "mcp__server.", name: "tool")
        XCTAssertFalse(name.isDefaultNamespace())
        XCTAssertEqual(name.description, "mcp__server.tool")
    }

    func testWithDefaultNamespaceFillsEmpty() {
        XCTAssertEqual(ToolName(plain: "x").withDefaultNamespace().namespace, "functions")
        XCTAssertEqual(
            ToolName(namespace: "", name: "x").withDefaultNamespace().namespace,
            "functions"
        )
        XCTAssertEqual(
            ToolName(namespaced: "mcp", name: "x").withDefaultNamespace().namespace,
            "mcp"
        )
    }

    func testOrderingMatchesUpstream() {
        // Namespaced sorts by (namespace, name); plain sorts by (name, nil),
        // and nil sorts before any wrapped value.
        let plain = ToolName(plain: "abc")
        let namespaced = ToolName(namespaced: "abc", name: "abc")
        XCTAssertTrue(plain < namespaced)
        XCTAssertFalse(namespaced < plain)

        let a = ToolName(namespaced: "a", name: "z")
        let b = ToolName(namespaced: "b", name: "a")
        XCTAssertTrue(a < b)
    }

    func testCodableEmitsExplicitNullNamespace() throws {
        let data = try JSONEncoder().encode(ToolName(plain: "shell"))
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains("\"namespace\":null"), json)
        XCTAssertTrue(json.contains("\"name\":\"shell\""), json)

        let decoded = try JSONDecoder().decode(ToolName.self, from: data)
        XCTAssertEqual(decoded, ToolName(plain: "shell"))
    }
}
