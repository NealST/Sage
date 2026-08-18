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
}
