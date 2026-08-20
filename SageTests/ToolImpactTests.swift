import XCTest
@testable import Sage

final class ToolImpactTests: XCTestCase {
    func testObservationToolsSkipConfirmation() {
        for name in [
            "list_directory",
            "read_text_file",
            "search_files",
            "get_clipboard",
            "get_selected_text",
            "get_screen_info",
            "get_frontmost_app",
            "get_system_volume",
            "load_skill",
            "load_skill_resource",
            "recall_task_transcript",
            "manage_todo_list",
            "explore_subagent",
        ] {
            XCTAssertFalse(
                ToolDefinition.requiresConfirmation(forToolNamed: name),
                "\(name) should ReAct without confirmation"
            )
        }
    }

    func testMutatingToolsRequireConfirmation() {
        for name in [
            "write_text_file",
            "delete_file",
            "run_shell_command",
            "set_clipboard",
            "open_url",
            "notify",
            "save_skill",
            "run_skill_script",
            "mcp__demo__write",
        ] {
            XCTAssertTrue(
                ToolDefinition.requiresConfirmation(forToolNamed: name),
                "\(name) should wait for confirmation"
            )
        }
    }

    func testObservePlanRejectsMutatingTools() {
        XCTAssertThrowsError(
            try ToolInvocationDispatcher.assertMutatingToolsAllowed(
                for: "write_text_file",
                workPlanKind: .observe
            )
        )
        XCTAssertThrowsError(
            try ToolInvocationDispatcher.assertMutatingToolsAllowed(
                for: "run_shell_command",
                workPlanKind: .answer
            )
        )
        XCTAssertThrowsError(
            try ToolInvocationDispatcher.assertMutatingToolsAllowed(
                for: "run_skill_script",
                workPlanKind: nil
            )
        )
        XCTAssertNoThrow(
            try ToolInvocationDispatcher.assertMutatingToolsAllowed(
                for: "read_text_file",
                workPlanKind: .observe
            )
        )
        XCTAssertNoThrow(
            try ToolInvocationDispatcher.assertMutatingToolsAllowed(
                for: "recall_task_transcript",
                workPlanKind: .observe
            )
        )
        XCTAssertNoThrow(
            try ToolInvocationDispatcher.assertMutatingToolsAllowed(
                for: "write_text_file",
                workPlanKind: .act
            )
        )
    }

    func testDefinitionInfersImpactFromName() {
        let read = ToolDefinition(
            name: "read_text_file",
            description: "r",
            parameters: .schemaObject(properties: [:])
        )
        let write = ToolDefinition(
            name: "write_text_file",
            description: "w",
            parameters: .schemaObject(properties: [:])
        )
        XCTAssertFalse(read.requiresConfirmation)
        XCTAssertTrue(write.requiresConfirmation)
    }

    func testPipelineTimeoutCoversAllBackends() {
        XCTAssertEqual(
            ToolInvocationPipeline.timeoutDuration(for: "read_text_file"),
            toolExecutionTimeout
        )
        XCTAssertEqual(
            ToolInvocationPipeline.timeoutDuration(for: "mcp__demo__search"),
            .seconds(130)
        )
        XCTAssertEqual(
            ToolInvocationPipeline.timeoutDuration(for: "run_skill_script"),
            .seconds(130)
        )
    }

    func testMixedPlanRequiresConfirmation() {
        let plan = AgentPlan(
            summary: "mix",
            steps: [
                AgentStep(
                    toolCallID: "1",
                    toolName: "read_text_file",
                    argumentsJSON: "{}",
                    title: "Read"
                ),
                AgentStep(
                    toolCallID: "2",
                    toolName: "write_text_file",
                    argumentsJSON: "{}",
                    title: "Write"
                ),
            ]
        )
        XCTAssertTrue(plan.requiresConfirmation)
    }

    func testMCPGroupsAppearOnlyAboveThresholdAndUnlockPerServer() {
        let small = (0..<MCPToolGroupTool.groupingThreshold).map {
            ToolDefinition(
                name: "mcp__one__tool\($0)",
                description: "tool",
                parameters: .schemaObject(properties: [:])
            )
        }
        XCTAssertEqual(
            MCPToolGroupTool.groupedDefinitions(small, unlockedServerNames: []).count,
            small.count
        )

        let large = (0...MCPToolGroupTool.groupingThreshold).map {
            ToolDefinition(
                name: "mcp__one__tool\($0)",
                description: "tool",
                parameters: .schemaObject(properties: [:])
            )
        }
        let locked = MCPToolGroupTool.groupedDefinitions(large, unlockedServerNames: [])
        XCTAssertEqual(locked.map(\.name), ["mcp_group__one"])
        XCTAssertFalse(ToolDefinition.requiresConfirmation(forToolNamed: "mcp_group__one"))

        let unlocked = MCPToolGroupTool.groupedDefinitions(
            large,
            unlockedServerNames: ["one"]
        )
        XCTAssertEqual(unlocked.map(\.name).sorted(), large.map(\.name).sorted())
    }
}

final class ToolArgumentValidatorTests: XCTestCase {
    private let schema = JSONValue.schemaObject(
        properties: [
            "path": .stringProperty("Path"),
            "count": .intProperty("Count"),
            "mode": .object([
                "type": .string("string"),
                "enum": .array([.string("fast"), .string("safe")]),
            ]),
            "items": .object([
                "type": .string("array"),
                "items": .schemaObject(
                    properties: ["id": .intProperty("ID")],
                    required: ["id"]
                ),
            ]),
        ],
        required: ["path"]
    )

    func testAcceptsValidArgumentsAndUnknownOptionalFields() {
        XCTAssertNoThrow(
            try ToolArgumentValidator.validate(
                argumentsJSON: #"{"path":"~/x","count":2,"mode":"safe","extra":true}"#,
                against: schema
            )
        )
    }

    func testRejectsMalformedJSON() {
        XCTAssertThrowsError(
            try ToolArgumentValidator.validate(argumentsJSON: #"{"path":"x""#, against: schema)
        )
    }

    func testRejectsMissingRequiredField() {
        XCTAssertThrowsError(
            try ToolArgumentValidator.validate(argumentsJSON: #"{"count":2}"#, against: schema)
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("path"))
        }
    }

    func testRejectsWrongTypeAndEnum() {
        XCTAssertThrowsError(
            try ToolArgumentValidator.validate(
                argumentsJSON: #"{"path":"x","count":2.5}"#,
                against: schema
            )
        )
        XCTAssertThrowsError(
            try ToolArgumentValidator.validate(
                argumentsJSON: #"{"path":"x","mode":"turbo"}"#,
                against: schema
            )
        )
    }

    func testValidatesNestedArrayItems() {
        XCTAssertThrowsError(
            try ToolArgumentValidator.validate(
                argumentsJSON: #"{"path":"x","items":[{}]}"#,
                against: schema
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("items[0]"))
        }
    }
}
