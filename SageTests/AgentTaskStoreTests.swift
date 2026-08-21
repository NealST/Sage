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
    func testSubmitRejectsWhileAPlanIsPending() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SageTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let repository = GRDBTaskRepository(
            databaseURL: directory.appendingPathComponent("sage.sqlite"),
            legacyJSONURL: directory.appendingPathComponent("tasks.json")
        )
        let runtime = AgentRuntime(
            settings: .shared,
            tools: .makeDefault(),
            taskRepository: repository,
            skills: SkillSessionController()
        )
        _ = await runtime.taskStore.createAndActivateTask(relatedTo: [])
        let plan = AgentPlan(
            summary: "pending",
            steps: [
                AgentStep(
                    toolCallID: "c1",
                    toolName: "write_text_file",
                    argumentsJSON: "{}",
                    title: "Write"
                ),
            ]
        )
        _ = await runtime.taskStore.commit(appendEvents: [], deleteEventIDs: []) { task in
            task.pendingPlan = plan
        }
        runtime.state.enterAwaitingConfirmation()

        let accepted = await runtime.turns.performSubmit("follow up")
        XCTAssertFalse(accepted)
        guard case .failed(let message) = runtime.state.phase else {
            XCTFail("expected failed phase while a plan is pending")
            return
        }
        XCTAssertTrue(message.contains("pending plan"))
    }
}
