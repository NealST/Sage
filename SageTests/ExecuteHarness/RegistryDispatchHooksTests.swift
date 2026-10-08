@testable import Sage
import CodexCore
import CodexProtocol
import XCTest

final class ExecuteHarnessRegistryDispatchHooksTests: XCTestCase {
    private var projectRoot: URL?

    override func tearDown() {
        if let projectRoot {
            try? FileManager.default.removeItem(at: projectRoot)
        }
        super.tearDown()
    }

    func testPreToolUseDenyBlocksBeforeHandler() async throws {
        try writeHooks("""
        {
          "pre_tool_use": [
            { "tool": "echo_tool", "action": "deny", "reason": "nope" }
          ]
        }
        """)
        var handled = 0
        do {
            _ = try await dispatchEcho(onCall: { handled += 1; return "ok" })
            XCTFail("expected PreToolUse block")
        } catch let error as FunctionCallError {
            XCTAssertEqual(
                error,
                .respondToModel("Tool call blocked by PreToolUse hook: nope. Tool: echo_tool")
            )
        }
        XCTAssertEqual(handled, 0)
    }

    func testPostToolUseDenyRejectsAfterHandler() async throws {
        try writeHooks("""
        {
          "post_tool_use": [
            { "tool": "echo_tool", "action": "deny", "reason": "blocked result" }
          ]
        }
        """)
        var handled = 0
        do {
            _ = try await dispatchEcho(onCall: { handled += 1; return "ok" })
            XCTFail("expected PostToolUse block")
        } catch let error as FunctionCallError {
            XCTAssertEqual(
                error,
                .respondToModel("blocked result")
            )
        }
        XCTAssertEqual(handled, 1)
    }

    func testPreToolUseContinueRecordsAdditionalContexts() async throws {
        try writeHooks("""
        {
          "pre_tool_use": [
            { "tool": "echo_tool", "action": "continue", "reason": "remember cwd" }
          ]
        }
        """)
        let lock = NSLock()
        var contexts: [String] = []
        let result = try await dispatchEcho(
            onCall: { "ok" },
            onContexts: { extra in
                lock.lock()
                contexts.append(contentsOf: extra)
                lock.unlock()
            }
        )
        XCTAssertEqual(result.result.logOutput(), "ok")
        lock.lock()
        XCTAssertEqual(contexts, ["remember cwd"])
        lock.unlock()
    }

    func testApplyPatchPreBlockIncludesCommand() async throws {
        try writeHooks("""
        {
          "pre_tool_use": [
            { "tool": "apply_patch", "action": "deny", "reason": "unsafe" }
          ]
        }
        """)
        do {
            _ = try await dispatch(
                name: "apply_patch",
                arguments: #"{"command":"rm -rf /"}"#,
                onCall: { XCTFail("handler must not run"); return "ok" }
            )
            XCTFail("expected PreToolUse block")
        } catch let error as FunctionCallError {
            XCTAssertEqual(
                error,
                .respondToModel(
                    "Command blocked by PreToolUse hook: unsafe. Command: rm -rf /"
                )
            )
        }
    }

    func testPreToolUseScriptSeesRustToolFields() async throws {
        try writeHooks(#"""
        {
          "pre_tool_use": [
            { "run": "python3 -c \"import json,sys; d=json.load(sys.stdin); open('pre.txt','w').write(d.get('hook_event_name','')+'|'+d.get('tool_name','')+'|'+d.get('turn_id',''))\"" }
          ]
        }
        """#)
        _ = try await HarnessToolRegistry().dispatch(
            ToolInvocation(
                callId: "c1",
                toolName: ToolName(plain: "echo_tool"),
                payload: .function(arguments: "{}"),
                turnId: "turn-7",
                onSageToolCall: { _, _, _ in "ok" },
                hookProjectRoot: projectRoot,
                hookModel: "gpt-5"
            )
        )
        XCTAssertEqual(
            try String(contentsOf: projectRoot!.appendingPathComponent("pre.txt"), encoding: .utf8),
            "PreToolUse|echo_tool|turn-7"
        )
    }

    func testMissingProjectRootSkipsHooks() async throws {
        var handled = 0
        let result = try await HarnessToolRegistry().dispatch(
            ToolInvocation(
                callId: "c1",
                toolName: ToolName(plain: "echo_tool"),
                payload: .function(arguments: "{}"),
                onSageToolCall: { _, _, _ in
                    handled += 1
                    return "ok"
                }
            )
        )
        XCTAssertEqual(handled, 1)
        XCTAssertEqual(result.result.logOutput(), "ok")
    }

    private func dispatchEcho(
        onCall: @escaping () -> String,
        onContexts: (@Sendable ([String]) -> Void)? = nil
    ) async throws -> AnyToolResult {
        try await dispatch(name: "echo_tool", arguments: "{}", onCall: onCall, onContexts: onContexts)
    }

    private func dispatch(
        name: String,
        arguments: String,
        onCall: @escaping () -> String,
        onContexts: (@Sendable ([String]) -> Void)? = nil
    ) async throws -> AnyToolResult {
        try await HarnessToolRegistry().dispatch(
            ToolInvocation(
                callId: "c1",
                toolName: ToolName(plain: name),
                payload: .function(arguments: arguments),
                onSageToolCall: { _, _, _ in onCall() },
                hookProjectRoot: projectRoot,
                onAdditionalContexts: onContexts
            )
        )
    }

    private func writeHooks(_ json: String) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SageRegistryHooks-\(UUID().uuidString)", isDirectory: true)
        let sage = root.appendingPathComponent(".sage", isDirectory: true)
        try FileManager.default.createDirectory(at: sage, withIntermediateDirectories: true)
        try Data(json.utf8).write(to: sage.appendingPathComponent("hooks.json"))
        projectRoot = root
    }
}
