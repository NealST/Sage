//
//  TaskHarnessTests.swift
//  Sage
//
//  M3: one persistent harness Session per task — creation, reuse across
//  turns, retirement on task switch, rollout identity round-trip, execute
//  entry-point input semantics, per-turn service refresh, phase turns
//  (plan / review) riding the same session with full history continuity,
//  and the must-fix rework submitted as an explicit session turn.
//

@testable import Sage
import SageCore
import SageProtocol
import XCTest

@MainActor
final class TaskHarnessTests: XCTestCase {
    private var tempDirectory: URL?

    override func tearDown() async throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        try await super.tearDown()
    }

    func testSameTaskReusesHarnessAndThreadAcrossStarts() async throws {
        let runtime = try makeRuntime()
        _ = await runtime.taskStore.createAndActivateTask(relatedTo: [])
        _ = await runtime.taskStore.commit(
            appendEvents: [
                AgentEvent(kind: .userInput, content: "one"),
                AgentEvent(kind: .assistantResponse, content: "ok"),
                AgentEvent(kind: .userInput, content: "two"),
            ],
            deleteEventIDs: []
        ) { _ in }
        runtime.turns.execute.modelSampler = { _ in
            ModelTurn(content: "reply", toolCalls: [])
        }

        await runtime.turns.execute.start()

        let firstHarness = try XCTUnwrap(runtime.turns.taskHarness)
        // Creation's reverse mapping already recorded the last userInput, so
        // the first turn submits no extra input yet prompts on full history.
        XCTAssertTrue(runtime.turns.execute.harnessInput.isEmpty)
        let firstPrompt = try XCTUnwrap(runtime.turns.execute.harnessSampleConversations.last)
        XCTAssertTrue(firstPrompt.contains { $0.kind == .userInput && $0.content == "one" })
        XCTAssertTrue(firstPrompt.contains { $0.kind == .userInput && $0.content == "two" })

        _ = await runtime.taskStore.commit(
            appendEvents: [AgentEvent(kind: .userInput, content: "three")],
            deleteEventIDs: []
        ) { _ in }

        await runtime.turns.execute.start()

        let secondHarness = try XCTUnwrap(runtime.turns.taskHarness)
        XCTAssertTrue(secondHarness === firstHarness)
        XCTAssertEqual(secondHarness.threadId, firstHarness.threadId)
        XCTAssertEqual(runtime.turns.execute.harnessInput.count, 1)
        let secondPrompt = try XCTUnwrap(runtime.turns.execute.harnessSampleConversations.last)
        XCTAssertTrue(secondPrompt.contains { $0.kind == .userInput && $0.content == "three" })
        XCTAssertTrue(secondPrompt.contains { $0.kind == .userInput && $0.content == "two" })
    }

    func testTaskSwitchRebuildsHarnessAndShutsOldSessionDown() async throws {
        let runtime = try makeRuntime()
        let newTaskA = await runtime.taskStore.createAndActivateTask(relatedTo: [])
        let taskA = try XCTUnwrap(newTaskA)
        _ = await runtime.taskStore.commit(
            appendEvents: [AgentEvent(kind: .userInput, content: "a")],
            deleteEventIDs: []
        ) { _ in }
        let harnessA = try XCTUnwrap(runtime.turns.ensureTaskHarness())

        let newTaskB = await runtime.taskStore.createAndActivateTask(relatedTo: [])
        _ = try XCTUnwrap(newTaskB)
        let harnessB = try XCTUnwrap(runtime.turns.ensureTaskHarness())

        XCTAssertFalse(harnessB === harnessA)
        XCTAssertNotEqual(harnessB.threadId, harnessA.threadId)
        XCTAssertTrue(runtime.turns.taskHarness === harnessB)
        XCTAssertEqual(runtime.turns.harnessIdentity[taskA]?.0, harnessA.threadId)
        try await waitForShutdown(of: harnessA)
        XCTAssertFalse(harnessB.isShutDown)
    }

    func testRolloutPathSurvivesTaskSwitchRoundTrip() async throws {
        let runtime = try makeRuntime()
        let newTaskA = await runtime.taskStore.createAndActivateTask(relatedTo: [])
        let taskA = try XCTUnwrap(newTaskA)
        _ = await runtime.taskStore.commit(
            appendEvents: [AgentEvent(kind: .userInput, content: "a")],
            deleteEventIDs: []
        ) { _ in }
        let harnessA = try XCTUnwrap(runtime.turns.ensureTaskHarness())
        let home = try XCTUnwrap(tempDirectory)
        harnessA.session.state.sessionConfiguration.sageHome = home.path
        let answer = RetainedVerifiedAnswer(
            turnId: "t1",
            callId: "c1",
            questions: [RetainedVerifiedQuestion(question: "ok?", answer: "yes")],
            acceptanceOrder: 1
        )
        try harnessA.session.appendOwnedRolloutItems([verifiedAnswerRolloutItem(answer)])
        let rolloutPath = try XCTUnwrap(harnessA.rolloutPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: rolloutPath))

        let newTaskB = await runtime.taskStore.createAndActivateTask(relatedTo: [])
        _ = try XCTUnwrap(newTaskB)
        _ = try XCTUnwrap(runtime.turns.ensureTaskHarness())
        try await waitForShutdown(of: harnessA)

        await runtime.taskStore.activateTask(taskA)
        let harnessA2 = try XCTUnwrap(runtime.turns.ensureTaskHarness())

        XCTAssertEqual(harnessA2.threadId, harnessA.threadId)
        XCTAssertEqual(harnessA2.rolloutPath, rolloutPath)
    }

    func testExecuteEntryPointsInputSemantics() async throws {
        let runtime = try makeRuntime()
        _ = await runtime.taskStore.createAndActivateTask(relatedTo: [])
        _ = await runtime.taskStore.commit(
            appendEvents: [AgentEvent(kind: .userInput, content: "go")],
            deleteEventIDs: []
        ) { _ in }
        runtime.turns.execute.modelSampler = { _ in
            ModelTurn(content: "reply", toolCalls: [])
        }

        // Creation's reverse mapping already carries "go", so the first turn
        // submits no input; a newer userInput is what start() re-rails.
        await runtime.turns.execute.start()
        XCTAssertTrue(runtime.turns.execute.harnessInput.isEmpty)

        _ = await runtime.taskStore.commit(
            appendEvents: [AgentEvent(kind: .userInput, content: "again")],
            deleteEventIDs: []
        ) { _ in }
        await runtime.turns.execute.start()
        XCTAssertEqual(runtime.turns.execute.harnessInput.count, 1)

        await runtime.turns.execute.continueWithTools()
        XCTAssertTrue(runtime.turns.execute.harnessInput.isEmpty)

        await runtime.turns.execute.finishWithoutMoreTools()
        XCTAssertTrue(runtime.turns.execute.harnessInput.isEmpty)
    }

    func testPrepareExecuteTurnRefreshesStaleSnapshots() async throws {
        let runtime = try makeRuntime()
        _ = await runtime.taskStore.createAndActivateTask(relatedTo: [])
        _ = await runtime.taskStore.commit(
            appendEvents: [AgentEvent(kind: .userInput, content: "go")],
            deleteEventIDs: []
        ) { _ in }
        runtime.turns.execute.mcpVisibleCatalog = { [] }
        let skill = SkillRecord(
            name: "demo",
            description: "test",
            path: "/tmp/SKILL.md",
            enabled: true,
            scope: .global
        )
        var exposeSkill = false
        runtime.turns.execute.hookActivatedSkills = { exposeSkill ? [skill] : [] }
        let harness = try XCTUnwrap(runtime.turns.ensureTaskHarness())
        XCTAssertTrue(harness.session.services.mcpVisibleTools.isEmpty)
        XCTAssertTrue(harness.session.services.hookActivatedSkills.isEmpty)
        XCTAssertEqual(harness.executeTurnsStarted, 0)

        runtime.turns.execute.mcpVisibleCatalog = {
            [McpVisibleTool(name: "search", serverName: "srv")]
        }
        exposeSkill = true
        harness.prepareExecuteTurn()

        XCTAssertEqual(harness.executeTurnsStarted, 1)
        XCTAssertEqual(
            harness.session.services.mcpVisibleTools,
            [McpVisibleTool(name: "search", serverName: "srv")]
        )
        XCTAssertEqual(harness.session.services.hookActivatedSkills, [skill])

        harness.prepareExecuteTurn()
        XCTAssertEqual(harness.executeTurnsStarted, 2)
    }

    /// M3 acceptance: plan, execute, and review turns all ride one task
    /// Session — the review prompt carries the plan turn's message and the
    /// execute reply (history continuity), and the phase turn borrows the
    /// session without writing its phase prompt into the Execute slots.
    func testPhaseTurnsAndExecuteShareOneSessionHistory() async throws {
        let runtime = try makeRuntime()
        _ = await runtime.taskStore.createAndActivateTask(relatedTo: [])
        _ = await runtime.taskStore.commit(
            appendEvents: [AgentEvent(kind: .userInput, content: "one")],
            deleteEventIDs: []
        ) { _ in }

        let planner = runtime.turns.planner
        planner.phaseRunner.modelSampler = { _ in
            ModelTurn(content: "计划好了：先做 A。", toolCalls: [])
        }
        var reviewPrompts: [Prompt] = []
        runtime.turns.reviewer.phaseRunner.modelSampler = { prompt in
            reviewPrompts.append(prompt)
            return ModelTurn(content: #"{"must_fix":null,"optional":null}"#, toolCalls: [])
        }
        runtime.turns.execute.modelSampler = { _ in
            ModelTurn(content: "执行完毕。", toolCalls: [])
        }

        // Plan → execute → review, all on one task session (D1 topology).
        _ = try await planner.propose(userText: "one", skillAppendix: "", allowedSkillNames: [])
        let harness = try XCTUnwrap(runtime.turns.taskHarness)

        await runtime.turns.execute.start()

        XCTAssertTrue(runtime.turns.taskHarness === harness)
        guard case .completed = runtime.state.phase else {
            XCTFail("expected completed phase, got \(runtime.state.phase)")
            return
        }

        // The review prompt carried the whole task history: the reverse-
        // mapped user input, the plan turn's message, and the execute reply.
        XCTAssertEqual(reviewPrompts.count, 1)
        XCTAssertEqual(reviewPrompts[0].baseInstructions.text, ReviewAgent.systemPrompt)
        let reviewInput = promptAllText(reviewPrompts[0])
        XCTAssertTrue(reviewInput.contains("one"))
        XCTAssertTrue(reviewInput.contains("计划好了：先做 A。"))
        XCTAssertTrue(reviewInput.contains("执行完毕。"))

        // The phase turn never wrote its prompt into the session-level
        // Execute slot — the next execute turn still owns baseInstructions.
        XCTAssertNotEqual(
            harness.session.state.sessionConfiguration.baseInstructions,
            ReviewAgent.systemPrompt
        )
    }

    /// M3 acceptance: the must-fix rework loop closes on the same session,
    /// with the feedback submitted as an explicit user turn that reaches
    /// the model on top of the task history but never lands in the UI
    /// transcript.
    func testMustFixReworkSubmitsExplicitInputOnTaskSession() async throws {
        let runtime = try makeRuntime()
        _ = await runtime.taskStore.createAndActivateTask(relatedTo: [])
        _ = await runtime.taskStore.commit(
            appendEvents: [AgentEvent(kind: .userInput, content: "one")],
            deleteEventIDs: []
        ) { _ in }
        var executeReplies = ["第一版。", "第二版。"]
        runtime.turns.execute.modelSampler = { _ in
            ModelTurn(content: executeReplies.removeFirst(), toolCalls: [])
        }
        runtime.turns.reviewer.phaseRunner.modelSampler = { _ in
            ModelTurn(content: #"{"must_fix":null,"optional":null}"#, toolCalls: [])
        }

        await runtime.turns.execute.start()
        let harness = try XCTUnwrap(runtime.turns.taskHarness)

        await runtime.turns.applyReviewVerdict(.mustFixOnly("补上 brew 步骤"), draft: "第一版。")

        XCTAssertEqual(runtime.turns.reviewRounds, 1)
        // The feedback was set for the rework round, then cleared when the
        // second review passed and the loop completed.
        XCTAssertNil(runtime.state.reviewFeedback)
        // Same session — the rework round did not rebuild the harness.
        XCTAssertTrue(runtime.turns.taskHarness === harness)
        // The rework request is an explicit session turn…
        XCTAssertEqual(runtime.turns.execute.harnessInput.count, 1)
        let reworkInput = harnessInputText(runtime.turns.execute.harnessInput)
        XCTAssertTrue(reworkInput.contains("Review feedback"))
        XCTAssertTrue(reworkInput.contains("补上 brew 步骤"))
        // …that never lands in the UI transcript as a user message.
        XCTAssertFalse(
            runtime.state.events.contains { $0.kind == .userInput && $0.content.contains("brew") }
        )
        // The rework model saw the request on top of the full task history.
        let conversation = try XCTUnwrap(runtime.turns.execute.harnessSampleConversations.last)
        XCTAssertTrue(
            conversation.contains { $0.kind == .userInput && $0.content.contains("brew") }
        )
        XCTAssertTrue(
            conversation.contains { $0.kind == .assistantResponse && $0.content == "第一版。" }
        )
        // The loop closed through the second review.
        guard case .completed = runtime.state.phase else {
            XCTFail("expected completed phase, got \(runtime.state.phase)")
            return
        }
    }

    private func waitForShutdown(of harness: TaskHarness) async throws {
        for _ in 0..<200 where !harness.isShutDown {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(harness.isShutDown, "retired harness session did not shut down")
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

private func promptAllText(_ prompt: Prompt) -> String {
    prompt.input.compactMap { item -> String? in
        guard case .message(_, _, let content, _, _) = item else { return nil }
        return content.compactMap { contentItem -> String? in
            switch contentItem {
            case .inputText(let text), .outputText(let text):
                return text
            default:
                return nil
            }
        }.joined(separator: "\n")
    }.joined(separator: "\n")
}

private func harnessInputText(_ inputs: [SessionTurnInput]) -> String {
    inputs.compactMap { input -> String? in
        guard case .userInput(let content, _, _) = input else { return nil }
        return content.compactMap { part -> String? in
            if case .text(let text, _) = part { return text }
            return nil
        }.joined(separator: "\n")
    }.joined(separator: "\n")
}
