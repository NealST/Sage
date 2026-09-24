@testable import Sage
import XCTest

@MainActor
final class ExecuteHarnessTurnTests: XCTestCase {
    private var tempDirectory: URL?

    override func tearDown() async throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        try await super.tearDown()
    }

    func testFinalAnswerWithoutTools() async throws {
        let runtime = try makeRuntime()
        var reply: String?
        runtime.turns.execute.onCandidateReply = { reply = $0 }
        runtime.turns.execute.modelSampler = { includeTools in
            XCTAssertTrue(includeTools)
            return ModelTurn(content: "做好了", toolCalls: [])
        }

        await runtime.turns.execute.start()

        XCTAssertEqual(reply, "做好了")
        XCTAssertEqual(runtime.turns.execute.toolBatchCount, 0)
    }

    func testOneToolRoundThenFinalAnswer() async throws {
        let runtime = try makeRuntime()
        _ = await runtime.taskStore.createAndActivateTask(relatedTo: [])
        var rounds = 0
        var toolRuns = 0
        var reply: String?
        runtime.turns.execute.onCandidateReply = { reply = $0 }
        runtime.turns.execute.modelSampler = { _ in
            rounds += 1
            if rounds == 1 {
                return ModelTurn(
                    content: "先读",
                    toolCalls: [
                        ToolCallProposal(id: "c1", name: "read_text_file", argumentsJSON: "{}"),
                    ]
                )
            }
            return ModelTurn(content: "读完了", toolCalls: [])
        }
        runtime.turns.execute.runToolBatch = { _ in
            toolRuns += 1
            _ = await runtime.taskStore.commit(appendEvents: [], deleteEventIDs: []) { task in
                task.pendingPlan = nil
            }
            runtime.planProgress.clear()
            return .succeeded
        }

        await runtime.turns.execute.start()

        XCTAssertEqual(toolRuns, 1)
        XCTAssertEqual(reply, "读完了")
        XCTAssertEqual(runtime.turns.execute.toolBatchCount, 1)
        XCTAssertNil(runtime.state.activeTask?.pendingPlan)
    }

    func testNineToolRoundsDoNotStopAtTheOldBatchCap() async throws {
        let runtime = try makeRuntime()
        _ = await runtime.taskStore.createAndActivateTask(relatedTo: [])
        var rounds = 0
        var reply: String?
        runtime.turns.execute.onCandidateReply = { reply = $0 }
        runtime.turns.execute.modelSampler = { _ in
            rounds += 1
            if rounds <= 9 {
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
            return ModelTurn(content: "九轮之后仍能收尾", toolCalls: [])
        }
        runtime.turns.execute.runToolBatch = { _ in .succeeded }

        await runtime.turns.execute.start()

        XCTAssertEqual(reply, "九轮之后仍能收尾")
        XCTAssertEqual(runtime.turns.execute.toolBatchCount, 9)
        XCTAssertTrue(runtime.turns.execute.canOfferMoreTools)
    }

    func testStopCancelsTheModelRequest() async throws {
        let runtime = try makeRuntime()
        var stopped = false
        var reply: String?
        runtime.turns.execute.onCandidateReply = { reply = $0 }
        runtime.turns.execute.handleStop = { _ in
            stopped = true
        }
        runtime.turns.execute.modelSampler = { _ in
            throw CancellationError()
        }

        await runtime.turns.execute.start()

        XCTAssertTrue(stopped)
        XCTAssertNil(reply)
    }

    func testObservePlanRejectsWritesBeforeTheToolRunner() async throws {
        let runtime = try makeRuntime()
        _ = await runtime.taskStore.createAndActivateTask(relatedTo: [])
        _ = await runtime.taskStore.commit(appendEvents: [], deleteEventIDs: []) { task in
            task.workPlan = WorkPlan(
                kind: .observe,
                intent: "看看 README",
                approach: "只读。"
            )
        }
        var rounds = 0
        var toolRuns = 0
        var reply: String?
        runtime.turns.execute.onCandidateReply = { reply = $0 }
        runtime.turns.execute.modelSampler = { _ in
            rounds += 1
            if rounds == 1 {
                return ModelTurn(
                    content: "",
                    toolCalls: [
                        ToolCallProposal(id: "w1", name: "write_text_file", argumentsJSON: "{}"),
                    ]
                )
            }
            return ModelTurn(content: "只看了目录", toolCalls: [])
        }
        runtime.turns.execute.runToolBatch = { _ in
            toolRuns += 1
            return .succeeded
        }

        await runtime.turns.execute.start()

        XCTAssertEqual(toolRuns, 0)
        XCTAssertEqual(reply, "只看了目录")
        let refusal = runtime.state.events.first { $0.kind == .toolResult && $0.toolCallID == "w1" }
        XCTAssertTrue(refusal?.content.hasPrefix("ERROR:") == true)
        XCTAssertTrue(refusal?.content.contains("observe plan") == true)
    }

    func testObservePlanRefusesWritesInsideAMixedBatch() async throws {
        let runtime = try makeRuntime()
        _ = await runtime.taskStore.createAndActivateTask(relatedTo: [])
        _ = await runtime.taskStore.commit(appendEvents: [], deleteEventIDs: []) { task in
            task.workPlan = WorkPlan(
                kind: .observe,
                intent: "看看 README",
                approach: "只读。"
            )
        }
        var rounds = 0
        var toolRuns = 0
        runtime.turns.execute.onCandidateReply = { _ in }
        runtime.turns.execute.modelSampler = { _ in
            rounds += 1
            if rounds > 1 {
                return ModelTurn(content: "只看了目录", toolCalls: [])
            }
            return ModelTurn(
                content: "",
                toolCalls: [
                    ToolCallProposal(id: "r1", name: "read_text_file", argumentsJSON: "{}"),
                    ToolCallProposal(id: "w1", name: "write_text_file", argumentsJSON: "{}"),
                ]
            )
        }
        runtime.turns.execute.runToolBatch = { _ in
            toolRuns += 1
            let names = runtime.planProgress.plan?.steps.map(\.toolName) ?? []
            XCTAssertEqual(names, ["read_text_file"])
            return .succeeded
        }

        await runtime.turns.execute.start()

        XCTAssertEqual(toolRuns, 1)
        let refusal = runtime.state.events.first { $0.kind == .toolResult && $0.toolCallID == "w1" }
        XCTAssertTrue(refusal?.content.hasPrefix("ERROR:") == true)
    }

    func testWorkPlanAppendixStaysOnTheExecutePrompt() async throws {
        let runtime = try makeRuntime()
        _ = await runtime.taskStore.createAndActivateTask(relatedTo: [])
        _ = await runtime.taskStore.commit(appendEvents: [], deleteEventIDs: []) { task in
            task.workPlan = WorkPlan(
                kind: .act,
                intent: "只改 README 的安装节",
                approach: "补一行 brew。"
            )
        }

        let assembly = await runtime.modelGateway.assemblePrompt(
            tools: [],
            workingMemory: nil,
            skillResult: nil
        )
        let system = assembly.events
            .filter { $0.kind == .systemInstruction }
            .map(\.content)
            .joined(separator: "\n")

        XCTAssertTrue(system.contains("Confirmed work plan"))
        XCTAssertTrue(system.contains("只改 README 的安装节"))
    }

    private func makeRuntime() throws -> AgentRuntime {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SageTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        tempDirectory = directory
        let repository = GRDBTaskRepository(
            databaseURL: directory.appendingPathComponent("sage.sqlite"),
            legacyJSONURL: directory.appendingPathComponent("tasks.json")
        )
        return AgentRuntime(
            settings: .shared,
            tools: .makeDefault(),
            taskRepository: repository,
            skills: SkillSessionController()
        )
    }
}
