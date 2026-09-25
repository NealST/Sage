//
//  items.swift
//  SageTests
//
//  Port of focused cases from codex-rs/protocol/src/items.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//

import Foundation
import XCTest
@testable import CodexProtocol
import CodexUtils

final class ItemsTests: XCTestCase {
    func testModelInvocationContextRoundTripViaCommandItem() throws {
        let context = ModelInvocationContext(modelSlug: "gpt-5", reasoningEffort: "high")
        XCTAssertEqual(context.modelSlug, "gpt-5")
        XCTAssertEqual(context.reasoningEffort, "high")

        let cwd = try PathUri.parse("file:///tmp")
        let item = CommandExecutionItem(
            sandboxType: .macSeatbelt,
            modelContext: context,
            id: "cmd-1",
            command: ["echo", "hi"],
            cwd: cwd,
            parsedCmd: [],
            source: .agent,
            status: .completed)
        let encoded = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(CommandExecutionItem.self, from: encoded)
        XCTAssertEqual(decoded.id, "cmd-1")
        XCTAssertEqual(decoded.command, ["echo", "hi"])
        XCTAssertNil(decoded.modelContext)
        XCTAssertNil(decoded.sandboxType)
    }

    func testPluginRelativePathsUseSafeWireShape() {
        XCTAssertTrue(isSafePluginRelativePath("scripts/run.py"))
        for path in [
            "",
            "/home/user/.codex/plugins/cache/sample/scripts/run.py",
            "C:/Users/user/.codex/plugins/cache/sample/scripts/run.py",
            "scripts/C:/run.py",
            #"\\server\share\sample\scripts\run.py"#,
            #"scripts\run.py"#,
            "scripts//run.py",
            "scripts/./run.py",
            "scripts/../run.py",
        ] {
            XCTAssertFalse(isSafePluginRelativePath(path), path)
        }
    }

    func testHookPromptParsesLegacySingleHookRunId() {
        let parsed = parseHookPromptFragment(
            #"<hook_prompt hook_run_id="hook-run-1">Retry with tests.</hook_prompt>"#)
        XCTAssertEqual(
            parsed,
            HookPromptFragment(text: "Retry with tests.", hookRunId: "hook-run-1"))
    }
}
