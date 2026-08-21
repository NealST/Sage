@testable import Sage
import XCTest

final class ToolBatchWaveTests: XCTestCase {
    func testObservationRunsShareAParallelWave() {
        let steps = [
            step("1", "read_text_file"),
            step("2", "list_directory"),
            step("3", "get_clipboard"),
        ]
        XCTAssertEqual(
            ToolBatchWave.partition(steps),
            [.parallel([0, 1, 2])]
        )
    }

    func testTwoReadsThenWriteAreParallelThenSerial() {
        let steps = [
            step("1", "read_text_file"),
            step("2", "list_directory"),
            step("3", "write_text_file"),
        ]
        XCTAssertEqual(
            ToolBatchWave.partition(steps),
            [.parallel([0, 1]), .serial(2)]
        )
    }

    func testShellAndTodoStaySerial() {
        let steps = [
            step("1", "run_shell_command"),
            step("2", "manage_todo_list"),
            step("3", "mcp__demo__search"),
        ]
        XCTAssertEqual(
            ToolBatchWave.partition(steps),
            [.serial(0), .serial(1), .serial(2)]
        )
    }

    func testSingleObservationIsSerial() {
        XCTAssertEqual(
            ToolBatchWave.partition([step("1", "read_text_file")]),
            [.serial(0)]
        )
    }

    func testExploreSubagentStaysSerial() {
        XCTAssertEqual(
            ToolBatchWave.partition([
                step("1", "read_text_file"),
                step("2", "explore_subagent"),
                step("3", "search_files"),
            ]),
            [.serial(0), .serial(1), .serial(2)]
        )
    }

    private func step(_ id: String, _ name: String) -> AgentStep {
        AgentStep(toolCallID: id, toolName: name, argumentsJSON: "{}", title: name)
    }
}

final class SessionToolAllowlistTests: XCTestCase {
    func testCombinationKeyIsStableAfterKeyReorder() {
        let firstKey = SessionToolAllowlist.combinationKey(
            name: "run_shell_command",
            argumentsJSON: #"{"command":"ls","cwd":"~"}"#
        )
        let reorderedKey = SessionToolAllowlist.combinationKey(
            name: "run_shell_command",
            argumentsJSON: #"{"cwd":"~","command":"ls"}"#
        )
        XCTAssertEqual(firstKey, reorderedKey)
        XCTAssertEqual(firstKey.count, 64)
    }

    func testDifferentCommandsGetDifferentKeys() {
        let listKey = SessionToolAllowlist.combinationKey(
            name: "run_shell_command",
            argumentsJSON: #"{"command":"ls"}"#
        )
        let pwdKey = SessionToolAllowlist.combinationKey(
            name: "run_shell_command",
            argumentsJSON: #"{"command":"pwd"}"#
        )
        XCTAssertNotEqual(listKey, pwdKey)
    }

    func testOnlyShellAndMCPNeedAGate() {
        XCTAssertTrue(SessionToolAllowlist.needsGate(forToolNamed: "run_shell_command"))
        XCTAssertTrue(SessionToolAllowlist.needsGate(forToolNamed: "mcp__files__write"))
        XCTAssertFalse(SessionToolAllowlist.needsGate(forToolNamed: "write_text_file"))
        XCTAssertFalse(SessionToolAllowlist.needsGate(forToolNamed: "read_text_file"))
    }
}

@MainActor
final class SessionToolAllowlistActorTests: XCTestCase {
    func testSessionRememberAndReset() {
        let list = SessionToolAllowlist()
        XCTAssertFalse(list.contains(name: "run_shell_command", argumentsJSON: #"{"command":"ls"}"#))
        list.allowThisSession(name: "run_shell_command", argumentsJSON: #"{"command":"ls"}"#)
        XCTAssertTrue(list.contains(name: "run_shell_command", argumentsJSON: #"{"command":"ls"}"#))
        XCTAssertFalse(list.contains(name: "run_shell_command", argumentsJSON: #"{"command":"pwd"}"#))
        list.reset()
        XCTAssertFalse(list.contains(name: "run_shell_command", argumentsJSON: #"{"command":"ls"}"#))
    }

    func testToolLevelAllowCoversAnyArguments() {
        let list = SessionToolAllowlist()
        list.allowToolThisSession(named: "run_shell_command")
        XCTAssertTrue(list.contains(name: "run_shell_command", argumentsJSON: #"{"command":"ls"}"#))
        XCTAssertTrue(list.contains(name: "run_shell_command", argumentsJSON: #"{"command":"pwd"}"#))
        XCTAssertFalse(list.contains(name: "mcp__demo__search", argumentsJSON: "{}"))
    }

    func testAllowOnceIsConsumedExactlyOnce() {
        let list = SessionToolAllowlist()
        let args = #"{"command":"ls"}"#
        list.allowOnce(name: "run_shell_command", argumentsJSON: args)
        XCTAssertTrue(list.consumeApproval(name: "run_shell_command", argumentsJSON: args))
        XCTAssertFalse(list.consumeApproval(name: "run_shell_command", argumentsJSON: args))
    }
}

final class ExecuteCapabilityReminderTests: XCTestCase {
    func testActReminderIsLiveDeltasOnly() {
        let text = ExecuteCapabilityReminder.make(
            planKind: .act,
            activatedSkillNames: ["swift-review"],
            mcpServerNames: ["github"],
            todos: [AgentTodoItem(id: 1, title: "Read README", status: .inProgress)]
        )
        XCTAssertTrue(text.contains("Work plan kind: act"))
        XCTAssertFalse(text.contains("home directory"))
        XCTAssertFalse(text.contains("Sandbox:"))
        XCTAssertFalse(text.contains("do not need re-approval"))
        XCTAssertTrue(text.contains("swift-review"))
        XCTAssertTrue(text.contains("github"))
        XCTAssertTrue(text.contains("1 open / 1 total"))
    }

    func testObserveReminderOmitsActGateCopy() {
        let text = ExecuteCapabilityReminder.make(
            planKind: .observe,
            activatedSkillNames: [],
            mcpServerNames: [],
            todos: []
        )
        XCTAssertTrue(text.contains("observe"))
        XCTAssertFalse(text.contains("File tools"))
    }

    func testMcpServerNamesDedupedInOrder() {
        let tools = [
            ToolDefinition(name: "mcp__git__status", description: "s", parameters: .schemaObject(properties: [:])),
            ToolDefinition(name: "mcp__git__diff", description: "d", parameters: .schemaObject(properties: [:])),
            ToolDefinition(name: "read_text_file", description: "r", parameters: .schemaObject(properties: [:])),
            ToolDefinition(name: "mcp__files__list", description: "l", parameters: .schemaObject(properties: [:])),
        ]
        XCTAssertEqual(
            ExecuteCapabilityReminder.mcpServerNames(from: tools),
            ["git", "files"]
        )
    }
}

final class ManageTodoListToolTests: XCTestCase {
    func testNormalizedRejectsTwoInProgress() {
        XCTAssertThrowsError(
            try ManageTodoListTool.normalized([
                AgentTodoItem(id: 1, title: "A", status: .inProgress),
                AgentTodoItem(id: 2, title: "B", status: .inProgress),
            ])
        )
    }

    func testNormalizedSortsAndTrims() throws {
        let items = try ManageTodoListTool.normalized([
            AgentTodoItem(id: 2, title: "  Later  ", status: .notStarted),
            AgentTodoItem(id: 1, title: "Now", status: .inProgress),
        ])
        XCTAssertEqual(items.map(\.id), [1, 2])
        XCTAssertEqual(items[1].title, "Later")
    }

    func testNormalizedAllowsEmptyList() throws {
        XCTAssertTrue(try ManageTodoListTool.normalized([]).isEmpty)
    }

    func testPromptAppendixEmptyWhenUnused() {
        XCTAssertEqual(ManageTodoListTool.promptAppendix([]), "")
        XCTAssertTrue(ManageTodoListTool.promptAppendix([
            AgentTodoItem(id: 1, title: "Ship it", status: .completed),
        ]).contains("manage_todo_list"))
    }
}

final class ExecuteAgentLimitTests: XCTestCase {
    func testDefaultLimitAndExtensionCap() {
        XCTAssertEqual(ExecuteAgent.defaultToolBatchLimit, 8)
        XCTAssertEqual(ExecuteAgent.maxToolBatchLimit, 64)
    }
}

final class ToolBatchRetryScopeTests: XCTestCase {
    func testRetryDeletesOnlyThisBatchErrorResults() {
        let plan = AgentPlan(
            summary: "batch",
            steps: [
                AgentStep(toolCallID: "new", toolName: "read_text_file", argumentsJSON: "{}", title: "Read"),
            ]
        )
        let earlier = AgentEvent(
            kind: .toolResult,
            content: "ERROR: old",
            toolCallID: "old"
        )
        let current = AgentEvent(
            kind: .toolResult,
            content: "ERROR: new",
            toolCallID: "new"
        )
        let ids = ToolBatchExecutor.errorToolResultIDs(
            in: [earlier, current],
            matching: plan
        )
        XCTAssertEqual(ids, [current.id])
    }

    func testSuccessfulToolCallIDsIgnoreErrors() {
        let success = AgentEvent(kind: .toolResult, content: "hello", toolCallID: "a")
        let err = AgentEvent(kind: .toolResult, content: "ERROR: nope", toolCallID: "b")
        XCTAssertEqual(AgentEventHelpers.successfulToolCallIDs(in: [success, err]), ["a"])
    }
}

final class AgentPendingPromptPersistenceTests: XCTestCase {
    func testRoundLimitPromptRoundTrips() throws {
        let prompt = AgentPendingPrompt.toolRoundLimit(currentLimit: 8, nextLimit: 16)
        let data = try JSONEncoder().encode(prompt)
        let decoded = try JSONDecoder().decode(AgentPendingPrompt.self, from: data)
        XCTAssertEqual(decoded, prompt)
    }

    func testToolApprovalPromptRoundTrips() throws {
        let prompt = AgentPendingPrompt.toolApproval(
            toolCallID: "1",
            toolName: "run_shell_command",
            argumentsJSON: #"{"command":"ls"}"#,
            title: "Run: ls"
        )
        let data = try JSONEncoder().encode(prompt)
        let decoded = try JSONDecoder().decode(AgentPendingPrompt.self, from: data)
        XCTAssertEqual(decoded, prompt)
    }
}

final class PreToolUseHookEvaluatorTests: XCTestCase {
    func testDenyWinsAndArgumentMatchingIsScoped() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sage = root.appendingPathComponent(".sage", isDirectory: true)
        try FileManager.default.createDirectory(at: sage, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let config = """
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
        """
        try Data(config.utf8).write(to: sage.appendingPathComponent("hooks.json"))

        let evaluator = PreToolUseHookEvaluator()
        let denied = await evaluator.evaluate(
            toolName: "run_shell_command",
            argumentsJSON: #"{"command":"sudo whoami"}"#,
            projectRoot: root,
            activatedSkills: []
        )
        XCTAssertEqual(denied, .deny("No sudo [hooks.json]"))

        let asked = await evaluator.evaluate(
            toolName: "run_shell_command",
            argumentsJSON: #"{"command":"pwd"}"#,
            projectRoot: root,
            activatedSkills: []
        )
        XCTAssertEqual(asked, .ask("Review shell [hooks.json]"))

        let allowed = await evaluator.evaluate(
            toolName: "read_text_file",
            argumentsJSON: #"{"path":"README.md"}"#,
            projectRoot: root,
            activatedSkills: []
        )
        XCTAssertEqual(allowed, .allow)
    }

    func testMalformedExistingConfigFailsClosed() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sage = root.appendingPathComponent(".sage", isDirectory: true)
        try FileManager.default.createDirectory(at: sage, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("{bad".utf8).write(to: sage.appendingPathComponent("hooks.json"))

        let decision = await PreToolUseHookEvaluator().evaluate(
            toolName: "read_text_file",
            argumentsJSON: #"{"path":"README.md"}"#,
            projectRoot: root,
            activatedSkills: []
        )
        guard case .deny(let reason) = decision else {
            XCTFail("Malformed hook config must fail closed")
            return
        }
        XCTAssertTrue(reason.contains("Invalid PreToolUse hook config"))
    }
}
