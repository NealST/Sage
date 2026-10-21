//
//  PlanAgentHarnessTests.swift
//  Sage
//
//  M2 acceptance for the plan phase turn: propose is one harness
//  runTurn. Visible prose streams through the pump with the work-plan
//  card reserved while JSON is in flight, the three read-only tools are
//  dispatchable, mutating calls are refused by the registry gate before
//  dispatch, and all three WorkPlan kinds still parse through the
//  unchanged adapter pipeline. Stop interrupts the turn.
//

@testable import Sage
import SageCore
import SageProtocol
import XCTest

@MainActor
final class PlanAgentHarnessTests: XCTestCase {
    private var tempDirectory: URL?

    override func tearDown() async throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        try await super.tearDown()
    }

    func testPlanInspectsThenParsesActPlan() async throws {
        let runtime = try makeRuntime()
        let planner = runtime.turns.planner
        _ = try await seedUserTurn(on: runtime, text: "给项目加安装说明")

        var rounds = 0
        var prompts: [Prompt] = []
        planner.phaseRunner.modelSampler = { prompt in
            prompts.append(prompt)
            rounds += 1
            if rounds == 1 {
                return ModelTurn(
                    content: "先看一下现有文档。",
                    toolCalls: [
                        ToolCallProposal(id: "l1", name: "list_directory", argumentsJSON: "{}"),
                        ToolCallProposal(id: "s1", name: "search_files", argumentsJSON: "{}"),
                    ]
                )
            }
            return ModelTurn(
                content: """
                我看完了。
                {"kind":"act","intent":"给项目加安装说明","approach":"在 README 补一节安装步骤","side_effects":"会改 README","thread":"continue","skills":[]}
                """,
                toolCalls: []
            )
        }
        var dispatched: [String] = []
        planner.phaseRunner.dispatchTool = { call in
            dispatched.append(call.name)
            return "ok:\(call.name)"
        }

        let proposed = try await planner.propose(
            userText: "给项目加安装说明",
            skillAppendix: "",
            allowedSkillNames: []
        )

        XCTAssertEqual(proposed.plan.kind, .act)
        XCTAssertEqual(proposed.plan.intent, "给项目加安装说明")
        XCTAssertEqual(proposed.plan.sideEffects, "会改 README")
        XCTAssertEqual(proposed.leadIn, "我看完了。")
        XCTAssertEqual(rounds, 2)
        XCTAssertEqual(Set(dispatched), ["list_directory", "search_files"])

        // The assembled prompt carries the plan system prompt, the
        // read-only tool set, and the thread context + request as the
        // user message.
        XCTAssertEqual(prompts[0].baseInstructions.text, PlanAgent.systemPrompt)
        XCTAssertEqual(visibleToolNames(prompts[0]), ["list_directory", "read_text_file", "search_files"])
        let userText = promptUserText(prompts[0])
        XCTAssertTrue(userText.contains("给项目加安装说明"))

        // The follow-up prompt carries the round-one tool outputs.
        XCTAssertEqual(
            Set(promptToolOutputTexts(prompts[1])),
            ["ok:list_directory", "ok:search_files"]
        )

        // Calls and results are committed to the transcript.
        let toolCalls = runtime.state.events.flatMap { $0.toolCalls ?? [] }
        XCTAssertEqual(Set(toolCalls.map(\.name)), ["list_directory", "search_files"])
        let toolResults = runtime.state.events.filter { $0.kind == .toolResult }
        XCTAssertEqual(toolResults.count, 2)
        XCTAssertEqual(Set(toolResults.map(\.toolCallID)), ["l1", "s1"])

        // Prose streamed (pending or applied, either is the lead-in) and
        // the JSON reserved the work-plan card.
        XCTAssertEqual(runtime.streaming.currentVisibleText, "我看完了。")
        XCTAssertTrue(runtime.streamingPlayback.isReservingWorkPlan)
    }

    func testPlanAnswerKindStreamsDirectReply() async throws {
        let runtime = try makeRuntime()
        let planner = runtime.turns.planner
        _ = try await seedUserTurn(on: runtime, text: "讲个笑话")

        planner.phaseRunner.modelSampler = { _ in
            ModelTurn(content: "程序员最爱的两件事：写文档和不写文档。", toolCalls: [])
        }
        var dispatched = 0
        planner.phaseRunner.dispatchTool = { _ in
            dispatched += 1
            return "should not run"
        }

        let proposed = try await planner.propose(
            userText: "讲个笑话",
            skillAppendix: "",
            allowedSkillNames: []
        )

        XCTAssertEqual(proposed.plan.kind, .answer)
        XCTAssertEqual(proposed.plan.directReply, "程序员最爱的两件事：写文档和不写文档。")
        XCTAssertEqual(dispatched, 0)
        XCTAssertFalse(runtime.streamingPlayback.isReservingWorkPlan)
        XCTAssertEqual(runtime.streamingPlayback.text, "程序员最爱的两件事：写文档和不写文档。")
    }

    func testPlanObserveKindParsesWithoutConfirmation() async throws {
        let runtime = try makeRuntime()
        let planner = runtime.turns.planner
        _ = try await seedUserTurn(on: runtime, text: "看看磁盘还剩多少空间")

        planner.phaseRunner.modelSampler = { _ in
            ModelTurn(
                content: #"{"kind":"observe","intent":"查看磁盘空间","approach":"列出主目录大小","thread":"continue","skills":[]}"#,
                toolCalls: []
            )
        }

        let proposed = try await planner.propose(
            userText: "看看磁盘还剩多少空间",
            skillAppendix: "",
            allowedSkillNames: []
        )

        XCTAssertEqual(proposed.plan.kind, .observe)
        XCTAssertFalse(proposed.plan.requiresConfirmation)
        XCTAssertNil(proposed.plan.sideEffects)
        XCTAssertEqual(proposed.leadIn, "")
    }

    func testPlanFiltersRecalledSkillsAgainstCatalog() async throws {
        let runtime = try makeRuntime()
        let planner = runtime.turns.planner
        _ = try await seedUserTurn(on: runtime, text: "整理下载文件夹")

        planner.phaseRunner.modelSampler = { _ in
            ModelTurn(
                content: #"{"kind":"act","intent":"整理下载文件夹","approach":"按类型归档","side_effects":"会移动文件","thread":"continue","skills":["tidy-downloads","not-in-catalog"]}"#,
                toolCalls: []
            )
        }

        let proposed = try await planner.propose(
            userText: "整理下载文件夹",
            skillAppendix: "",
            allowedSkillNames: ["tidy-downloads"]
        )

        XCTAssertEqual(proposed.plan.skillNames, ["tidy-downloads"])
    }

    func testPlanMutatingToolCallIsRefusedBeforeDispatch() async throws {
        let runtime = try makeRuntime()
        let planner = runtime.turns.planner
        _ = try await seedUserTurn(on: runtime, text: "直接改掉 README")

        var rounds = 0
        var prompts: [Prompt] = []
        planner.phaseRunner.modelSampler = { prompt in
            prompts.append(prompt)
            rounds += 1
            if rounds == 1 {
                return ModelTurn(
                    content: "",
                    toolCalls: [ToolCallProposal(id: "w1", name: "write_text_file", argumentsJSON: "{}")]
                )
            }
            return ModelTurn(
                content: #"{"kind":"act","intent":"改 README","approach":"直接写","side_effects":"会改 README","thread":"continue","skills":[]}"#,
                toolCalls: []
            )
        }
        var dispatched = 0
        planner.phaseRunner.dispatchTool = { _ in
            dispatched += 1
            return "should not run"
        }

        let proposed = try await planner.propose(
            userText: "直接改掉 README",
            skillAppendix: "",
            allowedSkillNames: []
        )

        XCTAssertEqual(proposed.plan.kind, .act)
        XCTAssertEqual(dispatched, 0)
        let outputs = promptToolOutputTexts(prompts[1])
        XCTAssertEqual(outputs.count, 1)
        XCTAssertTrue(outputs.allSatisfy { $0.contains("not available this turn") })
        XCTAssertTrue(runtime.state.events.flatMap { $0.toolCalls ?? [] }.isEmpty)
        XCTAssertTrue(runtime.state.events.filter { $0.kind == .toolResult }.isEmpty)
    }

    func testPlanWithoutSkillHostStaysTextOnly() async throws {
        let runtime = try makeRuntime()
        let planner = runtime.turns.planner
        planner.skillHost = nil
        _ = try await seedUserTurn(on: runtime, text: "看一眼 README")

        var rounds = 0
        var prompts: [Prompt] = []
        planner.phaseRunner.modelSampler = { prompt in
            prompts.append(prompt)
            rounds += 1
            if rounds == 1 {
                return ModelTurn(
                    content: "",
                    toolCalls: [ToolCallProposal(id: "r1", name: "read_text_file", argumentsJSON: "{}")]
                )
            }
            return ModelTurn(content: "README 讲了安装方法。", toolCalls: [])
        }
        var dispatched = 0
        planner.phaseRunner.dispatchTool = { _ in
            dispatched += 1
            return "should not run"
        }

        let proposed = try await planner.propose(
            userText: "看一眼 README",
            skillAppendix: "",
            allowedSkillNames: []
        )

        XCTAssertEqual(proposed.plan.kind, .answer)
        XCTAssertEqual(rounds, 2)
        XCTAssertEqual(dispatched, 0)
        XCTAssertTrue(prompts[0].tools.isEmpty)
        XCTAssertTrue(
            promptToolOutputTexts(prompts[1]).allSatisfy { $0.contains("not available this turn") }
        )
    }

    func testStopInterruptsPlanTurn() async throws {
        let runtime = try makeRuntime()
        let planner = runtime.turns.planner
        _ = try await seedUserTurn(on: runtime, text: "整理下载文件夹")

        planner.phaseRunner.modelSampler = { _ in
            ModelTurn(
                content: "",
                toolCalls: [ToolCallProposal(id: "slow", name: "list_directory", argumentsJSON: "{}")]
            )
        }
        planner.phaseRunner.dispatchTool = { _ in
            try await Task.sleep(nanoseconds: 5_000_000_000)
            return "ok"
        }

        let planTask = Task {
            try await planner.propose(
                userText: "整理下载文件夹",
                skillAppendix: "",
                allowedSkillNames: []
            )
        }
        try await Task.sleep(nanoseconds: 300_000_000)
        planTask.cancel()

        do {
            _ = try await planTask.value
            XCTFail("expected cancellation to interrupt the plan turn")
        } catch is CancellationError {
        } catch {
            XCTFail("expected CancellationError, got \(error)")
        }
    }

    func testUnreadablePlanOutputThrows() async throws {
        let runtime = try makeRuntime()
        let planner = runtime.turns.planner
        _ = try await seedUserTurn(on: runtime, text: "随便")

        planner.phaseRunner.modelSampler = { _ in
            ModelTurn(content: "", toolCalls: [])
        }

        do {
            _ = try await planner.propose(
                userText: "随便",
                skillAppendix: "",
                allowedSkillNames: []
            )
            XCTFail("expected unreadable output to fail propose")
        } catch is PlanProposalError {
        } catch {
            XCTFail("expected PlanProposalError, got \(error)")
        }
    }

    private func seedUserTurn(on runtime: AgentRuntime, text: String) async throws -> UUID {
        let created = await runtime.taskStore.createAndActivateTask(relatedTo: [])
        let taskID = try XCTUnwrap(created)
        let persisted = await runtime.taskStore.commit(
            appendEvents: [AgentEvent(kind: .userInput, content: text)],
            deleteEventIDs: []
        ) { _ in }
        XCTAssertTrue(persisted)
        return taskID
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

private func visibleToolNames(_ prompt: Prompt) -> Set<String> {
    var names: Set<String> = []
    for tool in prompt.tools {
        if case .object(let fields) = tool,
           case .string(let name)? = fields["name"] {
            names.insert(name)
        }
    }
    return names
}

private func promptUserText(_ prompt: Prompt) -> String {
    prompt.input.compactMap { item -> String? in
        guard case .message(_, let role, let content, _, _) = item, role == "user" else { return nil }
        return content.compactMap { contentItem -> String? in
            if case .inputText(let text) = contentItem { return text }
            return nil
        }.joined(separator: "\n")
    }.joined(separator: "\n")
}

private func promptToolOutputTexts(_ prompt: Prompt) -> [String] {
    prompt.input.compactMap { item -> String? in
        guard case .functionCallOutput(_, _, _, _, let output, _) = item else { return nil }
        return output.body.toText() ?? output.description
    }
}
