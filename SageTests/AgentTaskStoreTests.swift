@testable import Sage
import XCTest

@MainActor
final class AgentTaskStoreTests: XCTestCase {
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

    func testSpawnScheduledTaskDoesNotMoveLastGeneralPointer() async throws {
        let fixture = try makeStore()
        let repository = fixture.repository
        let store = fixture.store
        let state = fixture.state
        let createdUser = await store.createAndActivateTask(relatedTo: [])
        let userID = try XCTUnwrap(createdUser)
        let lastBeforeSpawn = try await repository.lastGeneralTaskID()
        XCTAssertEqual(lastBeforeSpawn, userID)

        let schedule = ScheduleRecord(
            title: "Nightly inbox",
            kind: .agent,
            prompt: "Nightly inbox",
            cadence: .daily(hour: 3, minute: 0)
        )
        try await repository.upsertSchedule(schedule, scriptRun: nil)
        let spawned = await store.spawnScheduledTask(
            projectID: nil,
            summary: "Nightly inbox",
            originScheduleID: schedule.id
        )
        let spawnedID = try XCTUnwrap(spawned)
        XCTAssertNotEqual(spawnedID, userID)
        XCTAssertEqual(state.activeTaskID, spawnedID)
        let lastAfterSpawn = try await repository.lastGeneralTaskID()
        XCTAssertEqual(lastAfterSpawn, userID)
        XCTAssertNil(state.recentSummaries.first { $0.id == spawnedID })
    }

    func testActivateTaskSwitchesTheWindowThread() async throws {
        let fixture = try makeStore()
        let store = fixture.store
        let state = fixture.state
        let createdFirst = await store.createAndActivateTask(relatedTo: [])
        let first = try XCTUnwrap(createdFirst)
        _ = await store.commit(
            appendEvents: [AgentEvent(kind: .userInput, content: "keep first")],
            deleteEventIDs: []
        )
        let createdSecond = await store.beginNewTask(relatedTo: [])
        let second = try XCTUnwrap(createdSecond)
        XCTAssertEqual(state.activeTaskID, second)

        await store.activateTask(first)
        XCTAssertEqual(state.activeTaskID, first)
        XCTAssertEqual(state.phase, .idle)
    }

    func testApplyBeginNewCreatesFreshTask() async throws {
        let fixture = try makeStore()
        let store = fixture.store
        let state = fixture.state
        let createdFirst = await store.createAndActivateTask(relatedTo: [])
        let first = try XCTUnwrap(createdFirst)
        _ = await store.commit(
            appendEvents: [AgentEvent(kind: .userInput, content: "hello")],
            deleteEventIDs: []
        )
        let applied = await store.apply(.beginNew(reason: "explicit fresh start"))
        XCTAssertEqual(applied?.action, .beginNew)
        XCTAssertNotEqual(state.activeTaskID, first)
        XCTAssertEqual(state.phase, .idle)
    }

    func testRestorePhaseWaitsOnUnfinishedToolBatch() async throws {
        let fixture = try makeStore()
        let store = fixture.store
        let state = fixture.state
        _ = await store.createAndActivateTask(relatedTo: [])
        let plan = AgentPlan(
            summary: "Write a file",
            steps: [
                AgentStep(
                    toolCallID: "call_1",
                    toolName: "write_text_file",
                    argumentsJSON: "{}",
                    title: "Write"
                ),
            ]
        )
        let savedPending = await store.commit(appendEvents: [], deleteEventIDs: []) { task in
            task.pendingPlan = plan
            task.status = .awaitingApproval
        }
        XCTAssertTrue(savedPending)
        await store.restorePhaseFromActiveTask()
        XCTAssertEqual(state.phase, .awaitingConfirmation)
    }

    func testRestoreFailedStatusShowsRetryWithoutPendingPlan() async throws {
        let fixture = try makeStore()
        let store = fixture.store
        let state = fixture.state
        let repository = fixture.repository
        let created = await store.createAndActivateTask(relatedTo: [])
        let taskID = try XCTUnwrap(created)
        let message = "The work plan couldn't be read. Retry to try again."
        _ = await store.commit(
            appendEvents: [AgentEvent(kind: .userInput, content: "看一下项目")],
            deleteEventIDs: []
        ) { task in
            task.status = .failed
            task.lastFailureMessage = message
        }

        await store.restorePhaseFromActiveTask()
        XCTAssertEqual(state.phase, .failed(message: message))
        let reloaded = try await repository.loadTask(id: taskID)
        XCTAssertEqual(reloaded?.status, .failed)
        XCTAssertEqual(reloaded?.lastFailureMessage, message)
    }

    func testRestoreToolResultWithoutPendingPlanLooksInterrupted() async throws {
        let fixture = try makeStore()
        let store = fixture.store
        let state = fixture.state
        let repository = fixture.repository
        let created = await store.createAndActivateTask(relatedTo: [])
        let taskID = try XCTUnwrap(created)
        _ = await store.commit(
            appendEvents: [
                AgentEvent(kind: .userInput, content: "读 README"),
                AgentEvent(kind: .toolResult, content: "# Title", toolCallID: "c1"),
            ],
            deleteEventIDs: []
        ) { task in
            task.status = .active
            task.pendingPlan = nil
        }

        await store.restorePhaseFromActiveTask()
        XCTAssertEqual(
            state.phase,
            .failed(message: AgentTaskStore.interruptedAfterToolsMessage)
        )
        XCTAssertEqual(state.activeTask?.status, .failed)
        let reloaded = try await repository.loadTask(id: taskID)
        XCTAssertEqual(reloaded?.status, .failed)
        XCTAssertEqual(reloaded?.lastFailureMessage, AgentTaskStore.interruptedAfterToolsMessage)
    }

    func testRestoreUnapprovedWorkPlanShowsConfirmCard() async throws {
        let fixture = try makeStore()
        let store = fixture.store
        let state = fixture.state
        _ = await store.createAndActivateTask(relatedTo: [])
        _ = await store.commit(
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
            task.workPlanApproved = false
        }

        await store.restorePhaseFromActiveTask()
        XCTAssertEqual(state.phase, .awaitingConfirmation)
        XCTAssertFalse(state.activeTask?.workPlanApproved ?? true)
    }

    func testRestoreApprovedWorkPlanWithoutBatchShowsRetry() async throws {
        let fixture = try makeStore()
        let store = fixture.store
        let state = fixture.state
        let repository = fixture.repository
        let created = await store.createAndActivateTask(relatedTo: [])
        let taskID = try XCTUnwrap(created)
        _ = await store.commit(
            appendEvents: [AgentEvent(kind: .userInput, content: "改 README")],
            deleteEventIDs: []
        ) { task in
            task.workPlan = WorkPlan(
                kind: .act,
                intent: "改 README",
                approach: "只补一节。",
                sideEffects: "会改 README"
            )
            task.status = .active
            task.workPlanApproved = true
        }

        await store.restorePhaseFromActiveTask()
        XCTAssertEqual(
            state.phase,
            .failed(message: AgentTaskStore.interruptedAfterApprovalMessage)
        )
        XCTAssertEqual(state.activeTask?.status, .failed)
        XCTAssertEqual(state.activeTask?.workPlan?.intent, "改 README")
        XCTAssertEqual(state.activeTask?.workPlanApproved, true)
        let reloaded = try await repository.loadTask(id: taskID)
        XCTAssertEqual(reloaded?.status, .failed)
        XCTAssertEqual(reloaded?.workPlanApproved, true)
        XCTAssertEqual(reloaded?.lastFailureMessage, AgentTaskStore.interruptedAfterApprovalMessage)
    }

    func testBeginNewTaskDoesNotInheritWorkingMemory() async throws {
        let fixture = try makeStore()
        let repository = fixture.repository
        let store = fixture.store
        let state = fixture.state
        let createdFirst = await store.createAndActivateTask(relatedTo: [])
        let first = try XCTUnwrap(createdFirst)
        let foldedFrom = AgentEvent(kind: .userInput, content: "clean downloads")
        let foldedThrough = AgentEvent(kind: .assistantResponse, content: "listed files")
        let savedMemory = await store.commit(
            appendEvents: [foldedFrom, foldedThrough],
            deleteEventIDs: []
        ) { task in
            task.workingMemory = .makeStructured(
                foldedFromEventID: foldedFrom.id,
                foldedThroughEventID: foldedThrough.id,
                overview: "Clean Downloads"
            )
        }
        XCTAssertTrue(savedMemory)
        let createdSecond = await store.beginNewTask(relatedTo: [])
        let second = try XCTUnwrap(createdSecond)
        XCTAssertNotEqual(second, first)
        XCTAssertNil(state.activeTask?.workingMemory)

        let archived = try await repository.loadTask(id: first)
        XCTAssertEqual(archived?.workingMemory?.overview, "Clean Downloads")
    }

    func testActivateTaskCancelsInFlightWork() async throws {
        let fixture = try makeStore()
        let repository = fixture.repository
        let skills = SkillSessionController()
        let runtime = AgentRuntime(
            settings: .shared,
            tools: .makeDefault(),
            taskRepository: repository,
            skills: skills
        )
        let createdFirst = await runtime.taskStore.createAndActivateTask(relatedTo: [])
        let first = try XCTUnwrap(createdFirst)
        _ = await runtime.taskStore.commit(
            appendEvents: [AgentEvent(kind: .userInput, content: "keep")],
            deleteEventIDs: []
        )
        let createdSecond = await runtime.taskStore.beginNewTask(relatedTo: [])
        let second = try XCTUnwrap(createdSecond)
        XCTAssertEqual(runtime.state.activeTaskID, second)

        let started = expectation(description: "busy")
        let work = Task {
            await runtime.operations.run {
                started.fulfill()
                try? await Task.sleep(for: .seconds(8))
            }
        }
        await fulfillment(of: [started], timeout: 2)
        XCTAssertTrue(runtime.state.isBusy)

        await runtime.activateTask(first)
        await work.value
        XCTAssertFalse(runtime.state.isBusy)
        XCTAssertEqual(runtime.state.activeTaskID, first)
    }

    private func makeStore() throws -> AgentStoreFixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SageTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        tempDirectory = directory
        let repository = GRDBTaskRepository(
            databaseURL: directory.appendingPathComponent("sage.sqlite"),
            legacyJSONURL: directory.appendingPathComponent("tasks.json")
        )
        let state = AgentSessionState()
        let store = AgentTaskStore(
            state: state,
            planProgress: PlanProgress(),
            taskRepository: repository,
            skills: SkillSessionController()
        )
        return AgentStoreFixture(repository: repository, store: store, state: state)
    }
}

private struct AgentStoreFixture {
    var repository: GRDBTaskRepository
    var store: AgentTaskStore
    var state: AgentSessionState
}

@MainActor
final class SessionOperationGateTests: XCTestCase {
    func testCancelInFlightClearsBusy() async {
        let state = AgentSessionState()
        let gate = SessionOperationGate(state: state)
        let started = expectation(description: "busy")
        let work = Task {
            await gate.run {
                started.fulfill()
                try? await Task.sleep(for: .seconds(8))
            }
        }
        await fulfillment(of: [started], timeout: 2)
        XCTAssertTrue(state.isBusy)
        await gate.cancelInFlight()
        await work.value
        XCTAssertFalse(state.isBusy)
    }

    func testPhaseWritesGoThroughSessionMethods() {
        let state = AgentSessionState()
        XCTAssertEqual(state.phase, .idle)
        state.enterThinking()
        XCTAssertEqual(state.phase, .thinking)
        state.enterFailed(message: "nope")
        XCTAssertEqual(state.phase, .failed(message: "nope"))
        state.clearFailedPhase()
        XCTAssertEqual(state.phase, .idle)
        state.setBusy(true)
        XCTAssertTrue(state.isBusy)
        state.setBusy(false)
        XCTAssertFalse(state.isBusy)
    }
}

@MainActor
final class TurnCoordinatorRoutingTests: XCTestCase {
    func testSubmitDiscardsUnconfirmedPlanThenAccepts() async throws {
        let runtime = try makeIsolatedRuntime()
        defer { runtime.cleanup() }

        _ = await runtime.instance.taskStore.createAndActivateTask(relatedTo: [])
        _ = await runtime.instance.taskStore.commit(
            appendEvents: [unexecutedWriteProposal(id: "c1")],
            deleteEventIDs: []
        ) { task in
            task.pendingPlan = AgentPlan(
                summary: "pending",
                steps: [
                    AgentStep(toolCallID: "c1", toolName: "write_text_file", argumentsJSON: "{}", title: "Write"),
                ]
            )
            task.workPlan = WorkPlan(kind: .act, intent: "改文件", approach: "写一处。", sideEffects: "会改文件")
        }
        runtime.instance.state.enterAwaitingConfirmation()

        _ = await runtime.instance.turns.performSubmit("follow up")
        XCTAssertNil(runtime.instance.state.activeTask?.pendingPlan)
        XCTAssertNil(runtime.instance.state.activeTask?.workPlan)
        XCTAssertFalse(runtime.instance.state.events.contains { eventProposesTool($0, id: "c1") })
        XCTAssertFalse(
            runtime.instance.state.events.contains { $0.content.contains("Cancelled. Nothing was changed.") }
        )
        if case .failed(let message) = runtime.instance.state.phase {
            XCTAssertFalse(message.contains("pending plan"))
        }
    }

    func testFrozenConfirmationIgnoresRun() async throws {
        let runtime = try makeIsolatedRuntime()
        defer { runtime.cleanup() }

        _ = await runtime.instance.taskStore.createAndActivateTask(relatedTo: [])
        _ = await runtime.instance.taskStore.commit(appendEvents: [], deleteEventIDs: []) { task in
            task.workPlan = WorkPlan(kind: .act, intent: "改文件", approach: "写一处。", sideEffects: "会改文件")
        }
        runtime.instance.state.enterAwaitingConfirmation()
        XCTAssertFalse(runtime.instance.state.shouldDisableConfirmationActions)
        runtime.instance.freezeConfirmationActions()
        XCTAssertTrue(runtime.instance.state.shouldDisableConfirmationActions)

        await runtime.instance.confirmWorkPlan()
        XCTAssertEqual(runtime.instance.state.phase, .awaitingConfirmation)
        XCTAssertNotNil(runtime.instance.state.activeTask?.workPlan)
    }

    private func eventProposesTool(_ event: AgentEvent, id: String) -> Bool {
        event.kind == .assistantResponse && (event.toolCalls ?? []).contains { $0.id == id }
    }

    private func unexecutedWriteProposal(id: String) -> AgentEvent {
        AgentEvent(
            kind: .assistantResponse,
            content: "",
            toolCalls: [ToolCallRecord(id: id, name: "write_text_file", argumentsJSON: "{}")]
        )
    }

    private func makeIsolatedRuntime() throws -> (instance: AgentRuntime, cleanup: () -> Void) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SageTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let repository = GRDBTaskRepository(
            databaseURL: directory.appendingPathComponent("sage.sqlite"),
            legacyJSONURL: directory.appendingPathComponent("tasks.json")
        )
        let instance = AgentRuntime(
            settings: .shared,
            tools: .makeDefault(),
            taskRepository: repository,
            skills: SkillSessionController()
        )
        return (instance, { try? FileManager.default.removeItem(at: directory) })
    }
}
