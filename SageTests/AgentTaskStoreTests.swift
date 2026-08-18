import XCTest
@testable import Sage

@MainActor
final class AgentTaskStoreTests: XCTestCase {
    private var tempDirectory: URL!

    override func tearDown() async throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        try await super.tearDown()
    }

    func testSpawnScheduledTaskDoesNotMoveLastGeneralPointer() async throws {
        let (repository, store, state) = try makeStore()
        let userID = try XCTUnwrap(await store.createAndActivateTask(relatedTo: []))
        XCTAssertEqual(try await repository.lastGeneralTaskID(), userID)

        let spawnedID = try XCTUnwrap(
            await store.spawnScheduledTask(
                projectID: nil,
                summary: "Nightly inbox",
                originScheduleID: UUID()
            )
        )
        XCTAssertNotEqual(spawnedID, userID)
        XCTAssertEqual(state.activeTaskID, spawnedID)
        XCTAssertEqual(try await repository.lastGeneralTaskID(), userID)
        XCTAssertNil(state.recentSummaries.first { $0.id == spawnedID })
    }

    func testActivateTaskSwitchesTheWindowThread() async throws {
        let (_, store, state) = try makeStore()
        let first = try XCTUnwrap(await store.createAndActivateTask(relatedTo: []))
        _ = await store.commit(
            appendEvents: [AgentEvent(kind: .userInput, content: "keep first")],
            deleteEventIDs: []
        )
        let second = try XCTUnwrap(await store.beginNewTask(relatedTo: []))
        XCTAssertEqual(state.activeTaskID, second)

        await store.activateTask(first)
        XCTAssertEqual(state.activeTaskID, first)
        XCTAssertEqual(state.phase, .idle)
    }

    func testRestorePhaseWaitsOnUnfinishedToolBatch() async throws {
        let (_, store, state) = try makeStore()
        _ = try XCTUnwrap(await store.createAndActivateTask(relatedTo: []))
        let plan = AgentPlan(
            summary: "Write a file",
            steps: [
                AgentStep(
                    toolCallID: "call_1",
                    toolName: "write_text_file",
                    argumentsJSON: "{}",
                    title: "Write"
                )
            ]
        )
        XCTAssertTrue(
            await store.commit(appendEvents: [], deleteEventIDs: []) { task in
                task.pendingPlan = plan
                task.status = .awaitingApproval
            }
        )
        await store.restorePhaseFromActiveTask()
        XCTAssertEqual(state.phase, .awaitingConfirmation)
    }

    func testApplyBeginNewOpensAFreshTask() async throws {
        let (_, store, state) = try makeStore()
        let first = try XCTUnwrap(await store.createAndActivateTask(relatedTo: []))
        _ = await store.commit(
            appendEvents: [AgentEvent(kind: .userInput, content: "hello")],
            deleteEventIDs: []
        )
        let applied = await store.apply(.beginNew(reason: "explicit fresh start"))
        XCTAssertEqual(applied?.action, .beginNew)
        XCTAssertNotEqual(state.activeTaskID, first)
        XCTAssertEqual(state.phase, .idle)
    }

    func testActivateTaskCancelsInFlightWork() async throws {
        let (repository, _, _) = try makeStore()
        let skills = SkillSessionController()
        let runtime = AgentRuntime(
            settings: .shared,
            tools: .makeDefault(),
            taskRepository: repository,
            skills: skills
        )
        let first = try XCTUnwrap(await runtime.taskStore.createAndActivateTask(relatedTo: []))
        _ = await runtime.taskStore.commit(
            appendEvents: [AgentEvent(kind: .userInput, content: "keep")],
            deleteEventIDs: []
        )
        let second = try XCTUnwrap(await runtime.taskStore.beginNewTask(relatedTo: []))
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

    private func makeStore() throws -> (GRDBTaskRepository, AgentTaskStore, AgentSessionState) {
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
        return (repository, store, state)
    }
}

@MainActor
final class SessionOperationGateTests: XCTestCase {
    func testCancelInFlightClearsBusy() async {
        let state = AgentSessionState()
        let gate = SessionOperationGate(state: state)
        let started = expectation(description: "started")
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
        _ = try XCTUnwrap(await runtime.taskStore.createAndActivateTask(relatedTo: []))
        let plan = AgentPlan(
            summary: "pending",
            steps: [
                AgentStep(
                    toolCallID: "c1",
                    toolName: "write_text_file",
                    argumentsJSON: "{}",
                    title: "Write"
                )
            ]
        )
        _ = await runtime.taskStore.commit(appendEvents: [], deleteEventIDs: []) {
            $0.pendingPlan = plan
        }
        runtime.state.enterAwaitingConfirmation()

        let accepted = await runtime.turns.performSubmit("follow up")
        XCTAssertFalse(accepted)
        guard case .failed(let message) = runtime.state.phase else {
            return XCTFail("expected failed phase while a plan is pending")
        }
        XCTAssertTrue(message.contains("pending plan"))
    }
}
