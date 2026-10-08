@testable import Sage
import CodexProtocol
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

    func testUserPromptSubmitInputJSONCarriesRustFields() throws {
        let json = userPromptSubmitInputJSON(
            UserPromptSubmitHookInput(
                prompt: "look at src",
                sessionId: "thread-1",
                turnId: "turn-9",
                cwd: "/tmp/project",
                model: "gpt-5",
                permissionMode: "default"
            )
        )
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        )
        XCTAssertEqual(object["hook_event_name"] as? String, "UserPromptSubmit")
        XCTAssertEqual(object["prompt"] as? String, "look at src")
        XCTAssertEqual(object["session_id"] as? String, "thread-1")
        XCTAssertEqual(object["turn_id"] as? String, "turn-9")
        XCTAssertEqual(object["cwd"] as? String, "/tmp/project")
        XCTAssertEqual(object["model"] as? String, "gpt-5")
        XCTAssertEqual(object["permission_mode"] as? String, "default")
        XCTAssertNil(object["agent_id"])
    }

    func testCompactHookInputJSONCarriesRustTrigger() throws {
        let pre = compactHookInputJSON(
            CompactHookInput(
                eventName: "PreCompact",
                trigger: .auto,
                sessionId: "thread-1",
                turnId: "turn-3",
                cwd: "/tmp/project",
                model: "gpt-5"
            )
        )
        let preObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(pre.utf8)) as? [String: Any]
        )
        XCTAssertEqual(preObject["hook_event_name"] as? String, "PreCompact")
        XCTAssertEqual(preObject["trigger"] as? String, "auto")
        XCTAssertEqual(preObject["session_id"] as? String, "thread-1")
        XCTAssertEqual(preObject["turn_id"] as? String, "turn-3")
        XCTAssertEqual(preObject["model"] as? String, "gpt-5")

        let post = compactHookInputJSON(
            CompactHookInput(
                eventName: "PostCompact",
                trigger: .manual,
                sessionId: "thread-1",
                turnId: "turn-3",
                cwd: "/tmp/project",
                model: "gpt-5"
            )
        )
        let postObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(post.utf8)) as? [String: Any]
        )
        XCTAssertEqual(postObject["hook_event_name"] as? String, "PostCompact")
        XCTAssertEqual(postObject["trigger"] as? String, "manual")
    }

    func testPreCompactScriptReadsTriggerFromStdin() async throws {
        try writeHooks(#"""
        {
          "pre_compact": [
            { "run": "python3 -c \"import json,sys; d=json.load(sys.stdin); open('compact.txt','w').write(d.get('hook_event_name','')+'|'+d.get('trigger',''))\"" }
          ]
        }
        """#)
        let outcome = await HookRuntime.preCompact(
            projectRoot: projectRoot,
            trigger: .auto,
            sessionId: "sess-8",
            turnId: "t-2",
            cwd: projectRoot?.path,
            model: "gpt-5"
        )
        XCTAssertFalse(outcome.shouldStop)
        let written = try String(
            contentsOf: projectRoot!.appendingPathComponent("compact.txt"),
            encoding: .utf8
        )
        XCTAssertEqual(written, "PreCompact|auto")
    }

    func testLifecycleHookInputJSONCarriesRustFields() throws {
        let interrupt = interruptHookInputJSON(
            InterruptHookInput(
                sessionId: "thread-1",
                turnId: "turn-3",
                cwd: "/tmp/project",
                model: "gpt-5",
                permissionMode: "default"
            )
        )
        let interruptObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(interrupt.utf8)) as? [String: Any]
        )
        XCTAssertEqual(interruptObject["hook_event_name"] as? String, "Interrupt")
        XCTAssertEqual(interruptObject["session_id"] as? String, "thread-1")
        XCTAssertEqual(interruptObject["turn_id"] as? String, "turn-3")
        XCTAssertEqual(interruptObject["model"] as? String, "gpt-5")
        XCTAssertEqual(interruptObject["permission_mode"] as? String, "default")

        let sessionEnd = sessionEndHookInputJSON(
            SessionEndHookInput(
                sessionId: "thread-1",
                cwd: "/tmp/project",
                reason: .other
            )
        )
        let sessionEndObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(sessionEnd.utf8)) as? [String: Any]
        )
        XCTAssertEqual(sessionEndObject["hook_event_name"] as? String, "SessionEnd")
        XCTAssertEqual(sessionEndObject["reason"] as? String, "other")
        XCTAssertNil(sessionEndObject["turn_id"])

        let stop = stopHookInputJSON(
            StopHookInput(
                sessionId: "thread-1",
                turnId: "turn-3",
                cwd: "/tmp/project",
                model: "gpt-5",
                permissionMode: "bypassPermissions",
                stopHookActive: false,
                lastAssistantMessage: "done"
            )
        )
        let stopObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(stop.utf8)) as? [String: Any]
        )
        XCTAssertEqual(stopObject["hook_event_name"] as? String, "Stop")
        XCTAssertEqual(stopObject["stop_hook_active"] as? Bool, false)
        XCTAssertEqual(stopObject["last_assistant_message"] as? String, "done")
        XCTAssertEqual(stopObject["permission_mode"] as? String, "bypassPermissions")
    }

    func testInterruptScriptReadsTurnFieldsFromStdin() async throws {
        try writeHooks(#"""
        {
          "interrupt": [
            { "run": "python3 -c \"import json,sys; d=json.load(sys.stdin); open('interrupt.txt','w').write(d.get('hook_event_name','')+'|'+d.get('turn_id',''))\"" }
          ]
        }
        """#)
        let outcome = await HookRuntime.interrupt(
            projectRoot: projectRoot,
            sessionId: "sess-8",
            turnId: "t-2",
            cwd: projectRoot?.path,
            model: "gpt-5",
            permissionMode: "default"
        )
        XCTAssertFalse(outcome.shouldStop)
        let written = try String(
            contentsOf: projectRoot!.appendingPathComponent("interrupt.txt"),
            encoding: .utf8
        )
        XCTAssertEqual(written, "Interrupt|t-2")
    }

    func testStopScriptReadsStopHookActiveFromStdin() async throws {
        try writeHooks(#"""
        {
          "stop": [
            { "run": "python3 -c \"import json,sys; d=json.load(sys.stdin); open('stop.txt','w').write(d.get('hook_event_name','')+'|'+str(d.get('stop_hook_active')).lower()+'|'+str(d.get('last_assistant_message') or ''))\"" }
          ]
        }
        """#)
        let continuation = await HookRuntime.stopContinuation(
            projectRoot: projectRoot,
            alreadyActive: false,
            sessionId: "sess-8",
            turnId: "t-2",
            cwd: projectRoot?.path,
            model: "gpt-5",
            lastAssistantMessage: "shipped"
        )
        XCTAssertNil(continuation)
        let written = try String(
            contentsOf: projectRoot!.appendingPathComponent("stop.txt"),
            encoding: .utf8
        )
        XCTAssertEqual(written, "Stop|false|shipped")
    }

    func testToolUseHookInputJSONCarriesRustFields() throws {
        let pre = toolUseHookInputJSON(
            ToolUseHookInput(
                eventName: "PreToolUse",
                toolName: "apply_patch",
                toolInput: #"{"command":"ls"}"#,
                toolUseId: "call-1",
                sessionId: "thread-1",
                turnId: "turn-3",
                cwd: "/tmp/project",
                model: "gpt-5",
                permissionMode: "default"
            )
        )
        let preObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(pre.utf8)) as? [String: Any]
        )
        XCTAssertEqual(preObject["hook_event_name"] as? String, "PreToolUse")
        XCTAssertEqual(preObject["tool_name"] as? String, "apply_patch")
        XCTAssertEqual(preObject["tool_use_id"] as? String, "call-1")
        XCTAssertEqual(preObject["session_id"] as? String, "thread-1")
        XCTAssertEqual(preObject["turn_id"] as? String, "turn-3")
        let toolInput = try XCTUnwrap(preObject["tool_input"] as? [String: Any])
        XCTAssertEqual(toolInput["command"] as? String, "ls")
        XCTAssertNil(preObject["agent_id"])

        let permission = toolUseHookInputJSON(
            ToolUseHookInput(
                eventName: "PermissionRequest",
                toolName: "apply_patch",
                toolInput: "{}",
                toolUseId: "ignored",
                sessionId: "thread-1",
                turnId: "turn-3",
                cwd: "/tmp/project",
                model: "gpt-5",
                permissionMode: "default"
            )
        )
        let permissionObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(permission.utf8)) as? [String: Any]
        )
        XCTAssertEqual(permissionObject["hook_event_name"] as? String, "PermissionRequest")
        XCTAssertNil(permissionObject["tool_use_id"])

        let post = toolUseHookInputJSON(
            ToolUseHookInput(
                eventName: "PostToolUse",
                toolName: "echo_tool",
                toolInput: "{}",
                toolUseId: "call-1",
                sessionId: "thread-1",
                turnId: "turn-3",
                cwd: "/tmp/project",
                model: "gpt-5",
                permissionMode: "default",
                toolResponse: #"{"output":"ok"}"#
            )
        )
        let postObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(post.utf8)) as? [String: Any]
        )
        XCTAssertEqual(postObject["hook_event_name"] as? String, "PostToolUse")
        let response = try XCTUnwrap(postObject["tool_response"] as? [String: Any])
        XCTAssertEqual(response["output"] as? String, "ok")
    }

    func testPreToolUseScriptReadsToolNameFromStdin() async throws {
        try writeHooks(#"""
        {
          "pre_tool_use": [
            { "run": "python3 -c \"import json,sys; d=json.load(sys.stdin); open('pre.txt','w').write(d.get('hook_event_name','')+'|'+d.get('tool_name','')+'|'+d.get('tool_use_id',''))\"" }
          ]
        }
        """#)
        let outcome = await HookRuntime.preToolUse(
            tool: "echo_tool",
            command: "{}",
            projectRoot: projectRoot,
            argumentsJSON: "{}",
            sessionId: "sess-8",
            turnId: "t-2",
            cwd: projectRoot?.path,
            model: "gpt-5",
            toolUseId: "call-9"
        )
        XCTAssertFalse(outcome.shouldStop)
        let written = try String(
            contentsOf: projectRoot!.appendingPathComponent("pre.txt"),
            encoding: .utf8
        )
        XCTAssertEqual(written, "PreToolUse|echo_tool|call-9")
    }

    func testUserPromptSubmitScriptReadsPromptFromStdin() async throws {
        try writeHooks(#"""
        {
          "user_prompt_submit": [
            { "run": "python3 -c \"import json,sys; d=json.load(sys.stdin); open('prompt.txt','w').write(d.get('prompt','')+'|'+d.get('turn_id',''))\"" }
          ]
        }
        """#)
        let outcome = await HookRuntime.userPromptSubmit(
            "summarize README",
            projectRoot: projectRoot,
            sessionId: "sess-2",
            turnId: "t-4",
            cwd: projectRoot?.path,
            model: "gpt-5.4",
            permissionMode: "default"
        )
        XCTAssertFalse(outcome.shouldStop)
        let written = try String(
            contentsOf: projectRoot!.appendingPathComponent("prompt.txt"),
            encoding: .utf8
        )
        XCTAssertEqual(written, "summarize README|t-4")
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

    func testSessionStartInputJSONCarriesRustSource() {
        let startup = sessionStartInputJSON(
            SessionStartHookInput(
                source: .startup,
                sessionId: "sess-1",
                cwd: "/tmp/project",
                model: "gpt-5",
                permissionMode: "default"
            )
        )
        XCTAssertTrue(startup.contains("\"hook_event_name\":\"SessionStart\""))
        XCTAssertTrue(startup.contains("\"source\":\"startup\""))
        XCTAssertTrue(startup.contains("\"cwd\":\"/tmp/project\""))
        XCTAssertTrue(startup.contains("\"session_id\":\"sess-1\""))
        XCTAssertTrue(startup.contains("\"model\":\"gpt-5\""))
        let compact = sessionStartInputJSON(
            SessionStartHookInput(
                source: .compact,
                sessionId: "sess-1",
                cwd: "/tmp/project",
                model: "gpt-5",
                permissionMode: "bypassPermissions"
            )
        )
        XCTAssertTrue(compact.contains("\"source\":\"compact\""))
        XCTAssertTrue(compact.contains("\"permission_mode\":\"bypassPermissions\""))
        XCTAssertEqual(hookPermissionMode(.never), "bypassPermissions")
        XCTAssertEqual(hookPermissionMode(.onRequest), "default")
    }

    func testSessionStartScriptReadsSourceFromStdin() async throws {
        try writeHooks(#"""
        {
          "session_start": [
            { "run": "python3 -c \"import json,sys; d=json.load(sys.stdin); open('source.txt','w').write(d.get('source',''))\"" }
          ]
        }
        """#)
        let start = await HookRuntime.sessionStart(
            projectRoot: projectRoot,
            source: .resume,
            sessionId: "thread-9",
            cwd: projectRoot?.path,
            model: "gpt-5.4",
            permissionMode: "default"
        )
        XCTAssertFalse(start.shouldStop)
        let written = try String(
            contentsOf: projectRoot!.appendingPathComponent("source.txt"),
            encoding: .utf8
        )
        XCTAssertEqual(written, "resume")
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

    func testPreToolUseDecisionMatchesEvaluatorAndAskDoesNotStopScripts() async throws {
        try writeHooks("""
        {
          "pre_tool_use": [
            {"tool":"run_*","action":"ask","reason":"Review shell"},
            {
              "tool":"run_shell_command",
              "action":"deny",
              "argument_contains":{"command":"sudo "},
              "reason":"No sudo"
            }
          ]
        }
        """)
        let denied = HookRuntime.preToolUseDecision(
            tool: "run_shell_command",
            argumentsJSON: #"{"command":"sudo whoami"}"#,
            projectRoot: projectRoot
        )
        XCTAssertEqual(denied, .deny("No sudo [hooks.json]"))
        let evaluatorDenied = await PreToolUseHookEvaluator().evaluate(
            toolName: "run_shell_command",
            argumentsJSON: #"{"command":"sudo whoami"}"#,
            projectRoot: projectRoot,
            activatedSkills: []
        )
        XCTAssertEqual(denied, evaluatorDenied)

        let asked = HookRuntime.preToolUseDecision(
            tool: "run_shell_command",
            argumentsJSON: #"{"command":"pwd"}"#,
            projectRoot: projectRoot
        )
        guard case .ask(let approval) = asked else {
            return XCTFail("expected ask")
        }
        XCTAssertEqual(approval.reason, "Review shell [hooks.json]")

        let outcome = await HookRuntime.preToolUse(
            tool: "run_shell_command",
            command: #"{"command":"pwd"}"#,
            projectRoot: projectRoot,
            argumentsJSON: #"{"command":"pwd"}"#
        )
        XCTAssertFalse(outcome.shouldStop)
    }

    func testSkillHooksJsonFeedsPreToolUseDecision() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SageHookSkill-\(UUID().uuidString)", isDirectory: true)
        let skillDir = root.appendingPathComponent("skill", isDirectory: true)
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
        projectRoot = root
        try Data("""
        {
          "pre_tool_use": [
            {"tool":"write_text_file","action":"deny","reason":"skill blocks writes"}
          ]
        }
        """.utf8).write(to: skillDir.appendingPathComponent("hooks.json"))
        let skill = SkillRecord(
            name: "demo",
            description: "test",
            path: skillDir.appendingPathComponent("SKILL.md").path,
            enabled: true,
            scope: .global
        )
        let denied = HookRuntime.preToolUseDecision(
            tool: "write_text_file",
            argumentsJSON: #"{"path":"a.txt"}"#,
            projectRoot: nil,
            activatedSkills: [skill]
        )
        XCTAssertEqual(denied, .deny("skill blocks writes [hooks.json]"))
    }

    func testMalformedHooksJsonFailsClosed() async {
        try? writeHooks("{bad")
        let decision = HookRuntime.preToolUseDecision(
            tool: "read_text_file",
            argumentsJSON: #"{"path":"README.md"}"#,
            projectRoot: projectRoot
        )
        guard case .deny(let reason) = decision else {
            return XCTFail("malformed hooks must fail closed")
        }
        XCTAssertTrue(reason.contains("Invalid PreToolUse hook config"))
        let outcome = await HookRuntime.sessionStart(projectRoot: projectRoot)
        XCTAssertTrue(outcome.shouldStop)
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
