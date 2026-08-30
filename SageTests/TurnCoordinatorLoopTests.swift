@testable import Sage
import XCTest

@MainActor
final class TurnCoordinatorLoopTests: XCTestCase {
    private var tempDirectory: URL?

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = nil
    }

    override func tearDown() async throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        try await super.tearDown()
    }

    func testRetryPathPrefersPendingToolBatch() async throws {
        let runtime = try makeRuntime()
        _ = await runtime.taskStore.createAndActivateTask(relatedTo: [])
        _ = await runtime.taskStore.commit(appendEvents: [], deleteEventIDs: []) { task in
            task.pendingPlan = AgentPlan(
                summary: "batch",
                steps: [
                    AgentStep(
                        toolCallID: "c1",
                        toolName: "read_text_file",
                        argumentsJSON: "{}",
                        title: "Read"
                    ),
                ]
            )
        }
        XCTAssertEqual(runtime.turns.retryPath(), .retryToolBatch)
    }

    func testRetryPathConfirmsUnapprovedActPlan() async throws {
        let runtime = try makeRuntime()
        _ = await runtime.taskStore.createAndActivateTask(relatedTo: [])
        _ = await runtime.taskStore.commit(
            appendEvents: [AgentEvent(kind: .userInput, content: "改 README")],
            deleteEventIDs: []
        ) { task in
            task.workPlan = WorkPlan(
                kind: .act,
                intent: "改 README",
                approach: "只补一节。",
                sideEffects: "会改 README"
            )
        }
        runtime.turns.planApproved = false
        XCTAssertEqual(runtime.turns.retryPath(), .confirmWorkPlan)
    }

    func testRetryPathReplansWhenWorkPlanIsMissing() async throws {
        let runtime = try makeRuntime()
        _ = await runtime.taskStore.createAndActivateTask(relatedTo: [])
        _ = await runtime.taskStore.commit(
            appendEvents: [AgentEvent(kind: .userInput, content: "看一下项目")],
            deleteEventIDs: []
        )
        runtime.turns.planApproved = false
        if runtime.settings.isConfigured {
            XCTAssertEqual(runtime.turns.retryPath(), .resumeModelTurn)
        } else {
            XCTAssertNil(runtime.turns.retryPath())
        }
        XCTAssertNotEqual(runtime.turns.retryPath(), .retryToolBatch)
        XCTAssertNotEqual(runtime.turns.retryPath(), .confirmWorkPlan)
    }

    func testFollowUpAppendixSeparatesReviewAndSteer() {
        let appendix = AgentModelGateway.followUpAppendix(
            reviewFeedback: "补安装步骤",
            steerInstruction: "改读 INSTALL"
        )
        XCTAssertTrue(appendix.contains("## Follow-up"))
        XCTAssertTrue(appendix.contains("补安装步骤"))
        XCTAssertTrue(appendix.contains("## Redirect"))
        XCTAssertTrue(appendix.contains("改读 INSTALL"))
        XCTAssertEqual(AgentModelGateway.reviewFeedbackAppendix(nil), "")
        XCTAssertEqual(AgentModelGateway.steerAppendix("   "), "")
    }

    func testInheritedEvidenceReusesTaskGrant() async throws {
        let runtime = try makeRuntime()
        _ = await runtime.taskStore.createAndActivateTask(relatedTo: [])
        let arguments = #"{"path":"~/.ssh/id_ed25519"}"#
        runtime.state.sessionAllowlist.allowThisTask(
            name: "read_text_file",
            argumentsJSON: arguments,
            policy: .home,
            scopeID: runtime.state.authorizationScopeID
        )
        let requirement = ToolAuthorizationPolicy.requirement(
            name: "read_text_file",
            argumentsJSON: arguments,
            policy: .home
        )
        XCTAssertNotNil(requirement)
        let evidence = runtime.host.inheritedAuthorizationEvidence(
            name: "read_text_file",
            argumentsJSON: arguments
        )
        XCTAssertEqual(evidence?.requirementKey, requirement?.stableKey)
        XCTAssertNil(
            runtime.host.inheritedAuthorizationEvidence(
                name: "read_text_file",
                argumentsJSON: #"{"path":"~/Documents/note.txt"}"#
            )
        )
    }

    func testSteerRetractsUnexecutedBatchAndClearsPendingPlan() async throws {
        let runtime = try makeRuntime()
        await seedUnexecutedReadBatch(on: runtime)
        runtime.turns.reviewRounds = 2
        runtime.turns.execute.extendToolBatchLimit()

        let steered = await runtime.turns.persistSteerTurn(
            QueuedUserTurn(text: "改读 INSTALL", attachments: [])
        )
        XCTAssertTrue(steered)
        XCTAssertNil(runtime.state.activeTask?.pendingPlan)
        XCTAssertNil(runtime.state.activeTask?.pendingPrompt)
        XCTAssertNil(runtime.state.pendingPrompt)
        XCTAssertFalse(runtime.planProgress.hasPlan)
        XCTAssertEqual(runtime.turns.reviewRounds, 0)
        XCTAssertEqual(runtime.turns.execute.toolBatchCount, 0)
        XCTAssertEqual(runtime.turns.execute.toolBatchLimit, ExecuteAgent.defaultToolBatchLimit)
        XCTAssertEqual(runtime.state.steerInstruction, "改读 INSTALL")
        XCTAssertNil(runtime.state.reviewFeedback)
        XCTAssertEqual(runtime.turns.latestUserEventID, runtime.state.events.last?.id)
        XCTAssertFalse(runtime.state.events.contains { $0.toolCalls?.contains { $0.id == "c1" } == true })
        XCTAssertEqual(runtime.state.events.last?.content, "改读 INSTALL")
    }

    func testAdoptTaskIsolatesPlanApprovedAndReviewRounds() async throws {
        let runtime = try makeRuntime()
        let createdFirst = await runtime.taskStore.createAndActivateTask(relatedTo: [])
        let first = try XCTUnwrap(createdFirst)
        _ = await runtime.taskStore.commit(
            appendEvents: [AgentEvent(kind: .userInput, content: "first")],
            deleteEventIDs: []
        )
        runtime.turns.planApproved = true
        runtime.turns.reviewRounds = 2

        let createdSecond = await runtime.taskStore.createAndActivateTask(relatedTo: [])
        let second = try XCTUnwrap(createdSecond)
        XCTAssertNotEqual(second, first)
        XCTAssertFalse(runtime.turns.planApproved)
        XCTAssertEqual(runtime.turns.reviewRounds, 0)

        runtime.turns.planApproved = true
        runtime.turns.reviewRounds = 1
        await runtime.activateTask(first)
        XCTAssertEqual(runtime.state.activeTaskID, first)
        XCTAssertTrue(runtime.turns.planApproved)
        XCTAssertEqual(runtime.turns.reviewRounds, 2)

        await runtime.activateTask(second)
        XCTAssertTrue(runtime.turns.planApproved)
        XCTAssertEqual(runtime.turns.reviewRounds, 1)
    }

    func testBeginNewTaskDropsClosedTurnLoop() async throws {
        let runtime = try makeRuntime()
        let createdFirst = await runtime.taskStore.createAndActivateTask(relatedTo: [])
        let first = try XCTUnwrap(createdFirst)
        _ = await runtime.taskStore.commit(
            appendEvents: [AgentEvent(kind: .userInput, content: "keep")],
            deleteEventIDs: []
        )
        runtime.turns.planApproved = true
        runtime.turns.reviewRounds = 2

        let createdSecond = await runtime.taskStore.beginNewTask(relatedTo: [])
        _ = try XCTUnwrap(createdSecond)
        XCTAssertFalse(runtime.turns.planApproved)
        XCTAssertEqual(runtime.turns.reviewRounds, 0)

        await runtime.activateTask(first)
        XCTAssertFalse(runtime.turns.planApproved)
        XCTAssertEqual(runtime.turns.reviewRounds, 0)
    }

    private func seedUnexecutedReadBatch(on runtime: AgentRuntime) async {
        _ = await runtime.taskStore.createAndActivateTask(relatedTo: [])
        let proposal = AgentEvent(
            kind: .assistantResponse,
            content: "",
            toolCalls: [
                ToolCallRecord(id: "c1", name: "read_text_file", argumentsJSON: "{}"),
            ]
        )
        _ = await runtime.taskStore.commit(
            appendEvents: [
                AgentEvent(kind: .userInput, content: "读 README"),
                proposal,
            ],
            deleteEventIDs: []
        ) { task in
            task.pendingPlan = AgentPlan(
                summary: "Read",
                steps: [
                    AgentStep(
                        toolCallID: "c1",
                        toolName: "read_text_file",
                        argumentsJSON: "{}",
                        title: "Read"
                    ),
                ]
            )
            task.pendingPrompt = .toolRoundLimit(currentLimit: 8, nextLimit: 16)
        }
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

final class UnexecutedToolProposalTests: XCTestCase {
    func testRetractsOnlyFullyUnexecutedAssistantEvents() {
        let unread = AgentEvent(
            kind: .assistantResponse,
            content: "",
            toolCalls: [ToolCallRecord(id: "a", name: "read_text_file", argumentsJSON: "{}")]
        )
        let mixed = AgentEvent(
            kind: .assistantResponse,
            content: "",
            toolCalls: [
                ToolCallRecord(id: "b", name: "read_text_file", argumentsJSON: "{}"),
                ToolCallRecord(id: "c", name: "list_directory", argumentsJSON: "{}"),
            ]
        )
        let result = AgentEvent(kind: .toolResult, content: "ok", toolCallID: "b")
        let ids = AgentEventHelpers.unexecutedToolProposalIDs(in: [unread, mixed, result])
        XCTAssertEqual(ids, [unread.id])
    }
}
