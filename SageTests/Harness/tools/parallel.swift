@testable import Sage
import XCTest

final class ExecuteHarnessParallelTests: XCTestCase {
    func testObservationsShareAParallelWave() {
        XCTAssertEqual(
            ParallelToolRuntime.partition([
                "read_text_file",
                "list_directory",
                "get_clipboard",
            ]),
            [.parallel([0, 1, 2])]
        )
    }

    func testPatchShellMCPTodoAndExploreStaySerial() {
        XCTAssertFalse(ParallelToolRuntime.supportsParallel("apply_patch"))
        XCTAssertFalse(ParallelToolRuntime.supportsParallel("run_shell_command"))
        XCTAssertFalse(ParallelToolRuntime.supportsParallel("write_text_file"))
        XCTAssertFalse(ParallelToolRuntime.supportsParallel("manage_todo_list"))
        XCTAssertFalse(ParallelToolRuntime.supportsParallel("explore_subagent"))
        XCTAssertFalse(ParallelToolRuntime.supportsParallel("save_skill"))
        XCTAssertFalse(ParallelToolRuntime.supportsParallel("run_skill_script"))
        XCTAssertFalse(ParallelToolRuntime.supportsParallel("mcp__demo__search"))
        XCTAssertFalse(ParallelToolRuntime.supportsParallel("mcp_group__demo"))
        XCTAssertFalse(ParallelToolRuntime.supportsParallel("set_clipboard"))
        XCTAssertEqual(
            ParallelToolRuntime.partition([
                "read_text_file",
                "apply_patch",
                "run_shell_command",
                "mcp__demo__search",
                "manage_todo_list",
                "set_clipboard",
                "explore_subagent",
            ]),
            [
                .serial(0),
                .serial(1),
                .serial(2),
                .serial(3),
                .serial(4),
                .serial(5),
                .serial(6),
            ]
        )
    }

    func testReadsThenPatchAreParallelThenSerial() {
        XCTAssertEqual(
            ParallelToolRuntime.partition([
                "read_text_file",
                "search_files",
                "apply_patch",
            ]),
            [.parallel([0, 1]), .serial(2)]
        )
    }

    func testSingleObservationIsSerial() {
        XCTAssertEqual(
            ParallelToolRuntime.partition(["read_text_file"]),
            [.serial(0)]
        )
    }

    func testWaveDelegationMatchesTheRuntime() {
        let steps = [
            AgentStep(toolCallID: "1", toolName: "read_text_file", argumentsJSON: "{}", title: "Read"),
            AgentStep(toolCallID: "2", toolName: "apply_patch", argumentsJSON: "{}", title: "Patch"),
        ]
        XCTAssertEqual(
            ToolBatchWave.partition(steps),
            ParallelToolRuntime.partition(steps.map(\.toolName))
        )
        XCTAssertEqual(
            ToolBatchWave.runsInParallel("list_directory"),
            ParallelToolRuntime.supportsParallel("list_directory")
        )
    }
}

@MainActor
final class ExecuteHarnessParallelRunTests: XCTestCase {
    func testRunKeepsCallOrderAcrossAParallelWave() async throws {
        let calls = [
            ToolCallProposal(id: "a", name: "read_text_file", argumentsJSON: "{}"),
            ToolCallProposal(id: "b", name: "list_directory", argumentsJSON: "{}"),
            ToolCallProposal(id: "c", name: "write_text_file", argumentsJSON: "{}"),
        ]
        var seen: [String] = []
        let results = try await ParallelToolRuntime.run(calls: calls) { call in
            seen.append(call.id)
            return "ok-\(call.id)"
        }
        XCTAssertEqual(results, ["ok-a", "ok-b", "ok-c"])
        XCTAssertEqual(Set(seen), ["a", "b", "c"])
    }

    func testSerialErrorStillStartsEveryCall() async {
        let calls = [
            ToolCallProposal(id: "a", name: "write_text_file", argumentsJSON: "{}"),
            ToolCallProposal(id: "b", name: "read_text_file", argumentsJSON: "{}"),
        ]
        var seen: [String] = []
        do {
            _ = try await ParallelToolRuntime.run(calls: calls) { call in
                seen.append(call.id)
                if call.id == "a" {
                    throw ToolError.operationFailed("blocked")
                }
                return "ok"
            }
            XCTFail("Expected the serial write to throw")
        } catch {
            XCTAssertEqual(Set(seen), ["a", "b"])
        }
    }
}
