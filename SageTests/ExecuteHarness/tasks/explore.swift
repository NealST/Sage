@testable import Sage
import XCTest

@MainActor
final class ExecuteHarnessExploreTests: XCTestCase {
    func testFinalAnswerWithoutTools() async throws {
        let host = DummyHost()
        let task = ExploreTask(request: makeRequest(host: host))
        task.modelSampler = { includeTools in
            XCTAssertTrue(includeTools)
            return ModelTurn(content: "README has the install steps.", toolCalls: [])
        }

        await Turn.run(task, includeTools: true)

        XCTAssertEqual(try task.finish(), "README has the install steps.")
        XCTAssertEqual(task.toolBatchCount, 0)
        XCTAssertFalse(task.events.contains { $0.kind == .toolResult })
    }

    func testOneReadBatchThenFinalAnswerUsesTheTurnLoop() async throws {
        let host = DummyHost()
        let task = ExploreTask(request: makeRequest(host: host))
        var rounds = 0
        var invoked: [String] = []
        task.modelSampler = { _ in
            rounds += 1
            if rounds == 1 {
                return ModelTurn(
                    content: "looking",
                    toolCalls: [
                        ToolCallProposal(id: "r1", name: "read_text_file", argumentsJSON: "{}"),
                        ToolCallProposal(id: "l1", name: "list_directory", argumentsJSON: "{}"),
                    ]
                )
            }
            return ModelTurn(content: "two files, no writes.", toolCalls: [])
        }
        task.invokeTool = { call in
            invoked.append(call.name)
            return "ok:\(call.name)"
        }

        await Turn.run(task, includeTools: true)

        XCTAssertEqual(try task.finish(), "two files, no writes.")
        XCTAssertEqual(task.toolBatchCount, 1)
        XCTAssertEqual(Set(invoked), ["read_text_file", "list_directory"])
        XCTAssertEqual(
            task.events.filter { $0.kind == .toolResult }.map(\.content),
            ["ok:read_text_file", "ok:list_directory"]
        )
    }

    func testWriteProposalIsRejectedWithoutInvokingTheTool() async throws {
        let host = DummyHost()
        let task = ExploreTask(request: makeRequest(host: host))
        var rounds = 0
        var invoked = 0
        task.modelSampler = { _ in
            rounds += 1
            if rounds == 1 {
                return ModelTurn(
                    content: "",
                    toolCalls: [
                        ToolCallProposal(id: "w1", name: "write_text_file", argumentsJSON: "{}"),
                        ToolCallProposal(id: "p1", name: "apply_patch", argumentsJSON: "{}"),
                    ]
                )
            }
            return ModelTurn(content: "stayed read-only.", toolCalls: [])
        }
        task.invokeTool = { _ in
            invoked += 1
            return "should not run"
        }

        await Turn.run(task, includeTools: true)

        XCTAssertEqual(try task.finish(), "stayed read-only.")
        XCTAssertEqual(invoked, 0)
        let errors = task.events.filter { $0.kind == .toolResult }.map(\.content)
        XCTAssertEqual(errors.count, 2)
        XCTAssertTrue(errors.allSatisfy { $0.hasPrefix("ERROR:") })
    }

    func testRoundLimitAsksForASummaryWithoutTools() async throws {
        let host = DummyHost()
        let task = ExploreTask(request: makeRequest(host: host))
        var includeFlags: [Bool] = []
        var rounds = 0
        task.modelSampler = { includeTools in
            includeFlags.append(includeTools)
            rounds += 1
            if includeTools {
                return ModelTurn(
                    content: "",
                    toolCalls: [
                        ToolCallProposal(
                            id: "c\(rounds)",
                            name: "read_text_file",
                            argumentsJSON: "{}"
                        ),
                    ]
                )
            }
            return ModelTurn(content: "limit summary", toolCalls: [])
        }
        task.invokeTool = { _ in "ok" }

        await Turn.run(task, includeTools: true)

        XCTAssertEqual(try task.finish(), "limit summary")
        XCTAssertEqual(task.toolBatchCount, ExploreTask.maxToolRounds)
        XCTAssertEqual(includeFlags.filter(\.self).count, ExploreTask.maxToolRounds)
        XCTAssertEqual(includeFlags.last, false)
        XCTAssertTrue(task.events.contains { event in
            event.kind == .userInput && event.content.contains("Tool-round limit")
        })
    }

    func testCancelThrowsAndDoesNotYieldFindings() async {
        let host = DummyHost()
        let task = ExploreTask(request: makeRequest(host: host))
        task.modelSampler = { _ in
            throw CancellationError()
        }

        await Turn.run(task, includeTools: true)

        XCTAssertThrowsError(try task.finish()) { error in
            XCTAssertTrue(error is CancellationError)
        }
    }

    func testParentTranscriptIsUntouched() async throws {
        let host = DummyHost()
        let task = ExploreTask(request: makeRequest(host: host))
        task.modelSampler = { _ in
            ModelTurn(content: "isolated findings", toolCalls: [])
        }

        await Turn.run(task, includeTools: true)

        XCTAssertEqual(try task.finish(), "isolated findings")
        XCTAssertTrue(task.events.contains { $0.kind == .systemInstruction })
        XCTAssertTrue(task.events.contains { $0.kind == .userInput })
    }

    private func makeRequest(host: DummyHost) -> ExploreSubagentRequest {
        ExploreSubagentRequest(
            task: "What is in README?",
            context: nil,
            instructions: nil,
            settings: ModelSettingsSnapshot(baseURL: "", model: "test", apiKey: ""),
            tools: .makeDefault(),
            pathGuardPolicy: .home,
            skillHost: host,
            activatedSkillNames: [],
            enabledSkills: []
        )
    }
}

@MainActor
private final class DummyHost: SkillToolHost {
    var activatedSkillNames: Set<String> = []
    var enabledSkills: [SkillRecord] = []
    var catalogSkills: [SkillRecord] = []
    var focusedProjectRoot: URL?

    func broadcastSkillsCatalogChange() async {}

    func executeToolInvocation(name: String, argumentsJSON: String) async throws -> String {
        "ok"
    }

    func runExploreSubagent(
        task: String,
        context: String?,
        instructions: String?,
        activatedSkillNames: Set<String>
    ) async throws -> String {
        ""
    }
}
