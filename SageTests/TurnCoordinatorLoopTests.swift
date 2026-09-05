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

    func testConfirmWorkPlanStartsExecuteWithoutDiscarding() async throws {
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
        runtime.state.enterAwaitingConfirmation()
        runtime.state.setBusy(true)
        XCTAssertFalse(runtime.state.shouldDisableConfirmationActions)
        runtime.state.setBusy(false)

        await runtime.confirmWorkPlan()

        XCTAssertTrue(runtime.turns.planApproved)
        XCTAssertEqual(runtime.state.activeTask?.workPlanApproved, true)
        XCTAssertNotNil(runtime.state.activeTask?.workPlan)
        XCTAssertFalse(runtime.state.confirmationActionsFrozen)
    }

    func testPresentOptionalReviewWaitsThenKeepReplyFinalizes() async throws {
        let runtime = try makeRuntime()
        _ = await runtime.taskStore.createAndActivateTask(relatedTo: [])
        _ = await runtime.taskStore.commit(
            appendEvents: [AgentEvent(kind: .userInput, content: "改 README")],
            deleteEventIDs: []
        ) { task in
            task.workPlan = WorkPlan(
                kind: .act,
                intent: "改 README",
                approach: "只补一节。"
            )
            task.workPlanApproved = true
        }

        await runtime.turns.presentReviewOptional(draft: "已经改好了。", message: "目录名可以更短")
        XCTAssertEqual(runtime.state.phase, .awaitingConfirmation)
        XCTAssertEqual(runtime.turnChrome, .reviewOptional)
        guard case .reviewOptional(_, let message) = runtime.state.pendingPrompt else {
            return XCTFail("expected optional review prompt")
        }
        XCTAssertEqual(message, "目录名可以更短")

        await runtime.turns.acceptOptionalReview()
        XCTAssertNil(runtime.state.pendingPrompt)
        guard case .completed = runtime.state.phase else {
            return XCTFail("expected completed, got \(runtime.state.phase)")
        }
        XCTAssertEqual(runtime.state.events.last?.content, "已经改好了。")
    }

    func testExhaustedMustFixWaitsInsteadOfShipping() async throws {
        let runtime = try makeRuntime()
        _ = await runtime.taskStore.createAndActivateTask(relatedTo: [])
        _ = await runtime.taskStore.commit(
            appendEvents: [AgentEvent(kind: .userInput, content: "复制到剪贴板")],
            deleteEventIDs: []
        ) { task in
            task.workPlan = WorkPlan(
                kind: .act,
                intent: "复制到剪贴板",
                approach: "set_clipboard"
            )
            task.workPlanApproved = true
        }
        runtime.turns.reviewRounds = ReviewAgent.maxRevisions

        await runtime.turns.applyReviewVerdict(
            .mustFixOnly("安装步骤还缺 brew"),
            draft: "已复制。"
        )

        XCTAssertEqual(runtime.state.phase, .awaitingConfirmation)
        XCTAssertEqual(runtime.turnChrome, .reviewMustFix)
        guard case .reviewMustFix(let draft, let message) = runtime.state.pendingPrompt else {
            return XCTFail("expected must-fix prompt after the revision cap")
        }
        XCTAssertEqual(draft, "已复制。")
        XCTAssertEqual(message, "安装步骤还缺 brew")
        XCTAssertNil(runtime.state.events.last { $0.kind == .assistantResponse })
    }

    func testAcceptExhaustedMustFixShipsTheDraft() async throws {
        let runtime = try makeRuntime()
        _ = await runtime.taskStore.createAndActivateTask(relatedTo: [])
        _ = await runtime.taskStore.commit(
            appendEvents: [AgentEvent(kind: .userInput, content: "复制到剪贴板")],
            deleteEventIDs: []
        ) { task in
            task.workPlan = WorkPlan(
                kind: .act,
                intent: "复制到剪贴板",
                approach: "set_clipboard"
            )
            task.workPlanApproved = true
        }

        await runtime.turns.presentReviewMustFix(
            draft: "已复制。",
            message: "安装步骤还缺 brew",
            waitForUser: true
        )
        await runtime.turns.acceptMustFixReview()

        guard case .completed = runtime.state.phase else {
            return XCTFail("expected completed, got \(runtime.state.phase)")
        }
        XCTAssertNil(runtime.state.pendingPrompt)
        XCTAssertEqual(runtime.state.events.last?.content, "已复制。")
    }

    func testApplyReviewVerdictOptionalWaits() async throws {
        let runtime = try makeRuntime()
        _ = await runtime.taskStore.createAndActivateTask(relatedTo: [])
        _ = await runtime.taskStore.commit(
            appendEvents: [AgentEvent(kind: .userInput, content: "改 README")],
            deleteEventIDs: []
        ) { task in
            task.workPlan = WorkPlan(
                kind: .act,
                intent: "改 README",
                approach: "只补一节。"
            )
            task.workPlanApproved = true
        }

        await runtime.turns.applyReviewVerdict(
            ReviewVerdict(mustFix: nil, optional: "目录名可以更短"),
            draft: "已经改好了。"
        )
        XCTAssertEqual(runtime.state.phase, .awaitingConfirmation)
        XCTAssertEqual(runtime.turnChrome, .reviewOptional)
    }

    func testPersistedApprovalRestoresRetryWithoutConfirmCard() async throws {
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
            task.status = .awaitingApproval
        }
        runtime.state.enterAwaitingConfirmation()

        let persisted = await runtime.turns.persistWorkPlanApproval()
        XCTAssertTrue(persisted)
        XCTAssertEqual(runtime.state.activeTask?.workPlanApproved, true)
        XCTAssertEqual(runtime.state.activeTask?.status, .active)

        runtime.turns.planApproved = false
        await runtime.taskStore.restorePhaseFromActiveTask()
        runtime.turns.adoptActiveTask()

        XCTAssertEqual(
            runtime.state.phase,
            .failed(message: AgentTaskStore.interruptedAfterApprovalMessage)
        )
        XCTAssertTrue(runtime.turns.planApproved)
        if runtime.settings.isConfigured {
            XCTAssertEqual(runtime.turns.retryPath(), .resumeModelTurn)
        }
        XCTAssertNotEqual(runtime.turns.retryPath(), .confirmWorkPlan)
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

    func testNewUserTurnDiscardsLeftoverWorkPlanSoRetryReplans() async throws {
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
        runtime.turns.planApproved = true

        let persisted = await runtime.turns.persistSubmittedUserEvent(
            "看看天气",
            route: .continueActive(reason: "User continued the current thread")
        )
        XCTAssertTrue(persisted)
        XCTAssertNil(runtime.state.activeTask?.workPlan)
        XCTAssertNil(runtime.state.activeTask?.pendingPlan)
        XCTAssertFalse(runtime.planProgress.hasPlan)
        XCTAssertEqual(runtime.state.events.last?.content, "看看天气")

        runtime.turns.planApproved = false
        if runtime.settings.isConfigured {
            XCTAssertEqual(runtime.turns.retryPath(), .resumeModelTurn)
        } else {
            XCTAssertNil(runtime.turns.retryPath())
        }
        XCTAssertNotEqual(runtime.turns.retryPath(), .confirmWorkPlan)
        XCTAssertNotEqual(runtime.turns.retryPath(), .retryToolBatch)
    }

    func testSteerDiscardsWorkPlanSoTheNewMessageIsReplanned() async throws {
        let runtime = try makeRuntime()
        _ = await runtime.taskStore.createAndActivateTask(relatedTo: [])
        _ = await runtime.taskStore.commit(
            appendEvents: [AgentEvent(kind: .userInput, content: "先看看 README")],
            deleteEventIDs: []
        ) { task in
            task.workPlan = WorkPlan(
                kind: .observe,
                intent: "先看看 README",
                approach: "只读。"
            )
        }
        runtime.turns.planApproved = true
        runtime.state.steerInstruction = "旧纠偏"
        runtime.state.reviewFeedback = "旧复核"

        let steered = await runtime.turns.persistSteerTurn(
            QueuedUserTurn(text: "算了，把开头重写一下", attachments: [])
        )
        XCTAssertTrue(steered)
        XCTAssertNil(runtime.state.activeTask?.workPlan)
        XCTAssertNil(runtime.state.activeTask?.pendingPlan)
        XCTAssertFalse(runtime.turns.planApproved)
        XCTAssertNil(runtime.state.steerInstruction)
        XCTAssertNil(runtime.state.reviewFeedback)
        XCTAssertEqual(runtime.state.events.last?.content, "算了，把开头重写一下")

        if runtime.settings.isConfigured {
            XCTAssertEqual(runtime.turns.retryPath(), .resumeModelTurn)
        } else {
            XCTAssertNil(runtime.turns.retryPath())
        }
        XCTAssertNotEqual(runtime.turns.retryPath(), .confirmWorkPlan)
        XCTAssertNotEqual(runtime.turns.retryPath(), .retryToolBatch)
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

    func testSubmitWhileAwaitingConfirmationOffersInterrupt() async throws {
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
        runtime.state.enterAwaitingConfirmation()

        let accepted = await runtime.submit("别改 README，改 INSTALL")
        XCTAssertTrue(accepted)
        XCTAssertEqual(runtime.state.turnInput.offer?.text, "别改 README，改 INSTALL")
        XCTAssertEqual(runtime.state.phase, .awaitingConfirmation)
        XCTAssertEqual(runtime.state.activeTask?.workPlan?.intent, "改 README")
        XCTAssertFalse(runtime.state.events.contains { $0.content == "别改 README，改 INSTALL" })
    }

    func testExplicitFreshStartStaysOnTaskAndOffersStartFresh() async throws {
        let runtime = try makeRuntime()
        let created = await runtime.taskStore.createAndActivateTask(relatedTo: [])
        let taskID = try XCTUnwrap(created)
        let prior = [
            AgentEvent(kind: .userInput, content: "整理 Downloads"),
            AgentEvent(kind: .assistantResponse, content: "Sorted."),
        ]
        _ = await runtime.taskStore.commit(appendEvents: prior, deleteEventIDs: []) { task in
            task.topic = "整理 Downloads"
        }
        runtime.turns.latestUserEventID = prior[0].id

        let routing = await runtime.turns.routeSubmittedTurn("新任务：帮我写一个脚本")
        XCTAssertEqual(routing?.route.action, .continueActive)
        XCTAssertEqual(routing?.route.shouldOfferFreshStart, true)
        XCTAssertEqual(runtime.state.activeTaskID, taskID)

        let steered = await runtime.turns.persistSteerTurn(
            QueuedUserTurn(text: "新任务：帮我写一个脚本", attachments: [])
        )
        XCTAssertTrue(steered)
        XCTAssertEqual(runtime.state.activeTaskID, taskID)
        XCTAssertEqual(runtime.state.topicDriftOffer?.taskID, taskID)
        XCTAssertEqual(runtime.state.topicDriftOffer?.topicLabel, "整理 Downloads")
        XCTAssertEqual(
            runtime.state.topicDriftOffer?.triggeringUserEventID,
            runtime.turns.latestUserEventID
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
        XCTAssertNil(runtime.state.steerInstruction)
        XCTAssertFalse(runtime.turns.planApproved)
        XCTAssertNil(runtime.state.activeTask?.workPlan)
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
            task.workPlan = WorkPlan(
                kind: .observe,
                intent: "读 README",
                approach: "只读。"
            )
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
