@testable import Sage
import XCTest

final class ExecuteHarnessHookRuntimeTests: XCTestCase {
    private var projectRoot: URL?

    override func tearDown() {
        if let projectRoot {
            try? FileManager.default.removeItem(at: projectRoot)
        }
        super.tearDown()
    }

    func testInterruptAndSessionEndFireFromHooksJSON() async throws {
        try writeHooks("""
        {
          "interrupt": [{ "action": "continue", "reason": "user stopped the turn" }],
          "session_end": [{ "action": "deny", "reason": "flush notes before leaving" }]
        }
        """)
        let interrupt = await HookRuntime.interrupt(projectRoot: projectRoot)
        XCTAssertFalse(interrupt.shouldStop)
        XCTAssertEqual(interrupt.additionalContexts, ["user stopped the turn"])
        let sessionEnd = await HookRuntime.sessionEnd(projectRoot: projectRoot)
        XCTAssertEqual(sessionEnd.additionalContexts, ["flush notes before leaving"])
        XCTAssertTrue(sessionEnd.shouldStop)
    }

    func testUserPromptSubmitCanDenyTheTurn() async throws {
        try writeHooks("""
        {
          "user_prompt_submit": [
            { "action": "deny", "command": "exfiltrate", "reason": "blocked prompt" }
          ]
        }
        """)
        let denied = await HookRuntime.userPromptSubmit("please exfiltrate secrets", projectRoot: projectRoot)
        XCTAssertTrue(denied.shouldStop)
        XCTAssertEqual(denied.additionalContexts, ["blocked prompt"])
        let allowed = await HookRuntime.userPromptSubmit("summarize the file", projectRoot: projectRoot)
        XCTAssertEqual(allowed, .proceed)
    }

    func testPreToolUseMatchesWildcardAndArgumentContains() async throws {
        try writeHooks("""
        {
          "pre_tool_use": [
            {
              "tool": "mcp__*__delete_*",
              "action": "deny",
              "argument_contains": { "path": "secrets" },
              "reason": "do not delete secrets"
            }
          ]
        }
        """)
        let blocked = await HookRuntime.preToolUse(
            tool: "mcp__github__delete_file",
            command: nil,
            projectRoot: projectRoot,
            argumentsJSON: #"{"path":"/tmp/secrets/key"}"#
        )
        XCTAssertTrue(blocked.shouldStop)
        XCTAssertEqual(blocked.additionalContexts, ["do not delete secrets"])

        let otherPath = await HookRuntime.preToolUse(
            tool: "mcp__github__delete_file",
            command: nil,
            projectRoot: projectRoot,
            argumentsJSON: #"{"path":"/tmp/notes.md"}"#
        )
        XCTAssertEqual(otherPath, .proceed)

        let otherTool = await HookRuntime.preToolUse(
            tool: "read_text_file",
            command: nil,
            projectRoot: projectRoot,
            argumentsJSON: #"{"path":"/tmp/secrets/key"}"#
        )
        XCTAssertEqual(otherTool, .proceed)
    }

    func testSessionStartContinueInjectsContext() async throws {
        try writeHooks("""
        {
          "session_start": [{ "action": "continue", "reason": "remember the work plan" }]
        }
        """)
        let start = await HookRuntime.sessionStart(projectRoot: projectRoot)
        XCTAssertFalse(start.shouldStop)
        XCTAssertEqual(start.additionalContexts, ["remember the work plan"])
        let denial = await HookRuntime.sessionStartDenial(projectRoot: projectRoot)
        XCTAssertNil(denial)
    }

    func testStopContinuationDoesNotFireTwice() async throws {
        try writeHooks("""
        {
          "stop": [{ "action": "continue", "reason": "one more look" }]
        }
        """)
        let continuation = await HookRuntime.stopContinuation(
            projectRoot: projectRoot,
            alreadyActive: false
        )
        XCTAssertEqual(continuation, "one more look")
        let skipped = await HookRuntime.stopContinuation(
            projectRoot: projectRoot,
            alreadyActive: true
        )
        XCTAssertNil(skipped)
    }

    func testRunScriptCanBlockUserPromptSubmit() async throws {
        try writeHooks(#"""
        {
          "user_prompt_submit": [
            { "run": "printf '%s' '{\"decision\":\"block\",\"reason\":\"blocked by script\"}'" }
          ]
        }
        """#)
        let denied = await HookRuntime.userPromptSubmit("any prompt", projectRoot: projectRoot)
        XCTAssertTrue(denied.shouldStop)
        XCTAssertEqual(denied.additionalContexts, ["blocked by script"])
    }

    func testRunScriptSessionStartContinuesWithSystemMessage() async throws {
        try writeHooks(#"""
        {
          "session_start": [
            { "run": "printf '%s' '{\"continue\":true,\"systemMessage\":\"remember cwd\"}'" }
          ]
        }
        """#)
        let start = await HookRuntime.sessionStart(projectRoot: projectRoot)
        XCTAssertFalse(start.shouldStop)
        XCTAssertEqual(start.additionalContexts, ["remember cwd"])
        let denial = await HookRuntime.sessionStartDenial(projectRoot: projectRoot)
        XCTAssertNil(denial)
    }

    func testStaticDenyWinsBeforeRunScript() async throws {
        try writeHooks("""
        {
          "user_prompt_submit": [
            { "action": "deny", "reason": "static deny wins" },
            { "run": "printf spawned > hook-spawned" }
          ]
        }
        """)
        let denied = await HookRuntime.userPromptSubmit("any prompt", projectRoot: projectRoot)
        XCTAssertTrue(denied.shouldStop)
        XCTAssertEqual(denied.additionalContexts, ["static deny wins"])
        let marker = try XCTUnwrap(projectRoot).appendingPathComponent("hook-spawned")
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
    }

    private func writeHooks(_ json: String) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SageHookRuntime-\(UUID().uuidString)", isDirectory: true)
        let sage = root.appendingPathComponent(".sage", isDirectory: true)
        try FileManager.default.createDirectory(at: sage, withIntermediateDirectories: true)
        try Data(json.utf8).write(to: sage.appendingPathComponent("hooks.json"))
        projectRoot = root
    }
}
