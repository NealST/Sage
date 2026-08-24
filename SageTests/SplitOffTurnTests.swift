@testable import Sage
import XCTest

@MainActor
final class SplitOffTurnTests: XCTestCase {
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

    func testSplitOffTurnMovesLastUserInputAndDropsLaterReplies() async throws {
        let fixture = try makeStore()
        let created = await fixture.store.createAndActivateTask(relatedTo: [])
        let originalID = try XCTUnwrap(created)
        let user1 = AgentEvent(kind: .userInput, content: "整理 Downloads")
        let assistant1 = AgentEvent(kind: .assistantResponse, content: "Sorted.")
        let user2 = AgentEvent(kind: .userInput, content: "Write a pre-commit hook")
        let assistant2 = AgentEvent(kind: .assistantResponse, content: "Sure, here is a hook.")
        let saved = await fixture.store.commit(
            appendEvents: [user1, assistant1, user2, assistant2],
            deleteEventIDs: []
        ) { task in
            task.topic = "整理 Downloads"
            task.abstract = "整理 Downloads"
            task.activatedSkillNames = ["swift-review"]
        }
        XCTAssertTrue(saved)
        fixture.state.activatedSkillNames = ["swift-review"]

        let split = await fixture.store.splitOffTurn(from: user2.id)
        let result = try XCTUnwrap(split)
        XCTAssertTrue(result.needsModelTurn)
        XCTAssertEqual(result.userQuery, "Write a pre-commit hook")
        XCTAssertNotEqual(result.newTaskID, originalID)
        XCTAssertEqual(fixture.state.activeTaskID, result.newTaskID)
        XCTAssertEqual(fixture.state.activeTask?.events.map(\.id), [user2.id])
        XCTAssertEqual(fixture.state.activeTask?.activatedSkillNames ?? [], [])
        XCTAssertEqual(fixture.state.activatedSkillNames, [])
        XCTAssertNil(fixture.state.topicDriftOffer)

        let archived = try await fixture.repository.loadTask(id: originalID)
        XCTAssertEqual(archived?.events.map(\.id), [user1.id, assistant1.id])
        XCTAssertEqual(archived?.topic, "整理 Downloads")
        XCTAssertEqual(archived?.status, .completed)
        XCTAssertNil(archived?.pendingPlan)
    }

    func testSplitOffTurnDeletesEmptyClosingTask() async throws {
        let fixture = try makeStore()
        let created = await fixture.store.createAndActivateTask(relatedTo: [])
        let originalID = try XCTUnwrap(created)
        let user = AgentEvent(kind: .userInput, content: "hello")
        let didCommit = await fixture.store.commit(appendEvents: [user], deleteEventIDs: [])
        XCTAssertTrue(didCommit)

        let result = await fixture.store.splitOffTurn(from: user.id)
        XCTAssertEqual(result?.newTaskID, fixture.state.activeTaskID)
        XCTAssertEqual(fixture.state.activeTask?.events.map(\.id), [user.id])
        let deleted = try await fixture.repository.loadTask(id: originalID)
        XCTAssertNil(deleted)
    }

    func testSplitOffTurnReturnsNilForUnknownEvent() async throws {
        let fixture = try makeStore()
        let created = await fixture.store.createAndActivateTask(relatedTo: [])
        let originalID = try XCTUnwrap(created)
        let didCommit = await fixture.store.commit(
            appendEvents: [AgentEvent(kind: .userInput, content: "stay")],
            deleteEventIDs: []
        )
        XCTAssertTrue(didCommit)

        let missing = await fixture.store.splitOffTurn(from: UUID())
        XCTAssertNil(missing)
        XCTAssertEqual(fixture.state.activeTaskID, originalID)
    }

    func testApplyThreadOfferThenSplitOffTurn() async throws {
        let runtime = try makeRuntime()
        let created = await runtime.taskStore.createAndActivateTask(relatedTo: [])
        let originalID = try XCTUnwrap(created)
        let user1 = AgentEvent(kind: .userInput, content: "整理 Downloads")
        let assistant1 = AgentEvent(kind: .assistantResponse, content: "Sorted.")
        let user2 = AgentEvent(kind: .userInput, content: "Write a pre-commit hook")
        let assistant2 = AgentEvent(kind: .assistantResponse, content: "Here is a hook.")
        let didCommit = await runtime.taskStore.commit(
            appendEvents: [user1, assistant1, user2, assistant2],
            deleteEventIDs: []
        ) { task in
            task.topic = "整理 Downloads"
        }
        XCTAssertTrue(didCommit)

        runtime.turns.latestUserEventID = user2.id
        runtime.turns.applyThreadOffer(from: Self.offerPlan)
        XCTAssertEqual(runtime.state.topicDriftOffer?.taskID, originalID)
        XCTAssertEqual(runtime.state.topicDriftOffer?.triggeringUserEventID, user2.id)
        XCTAssertEqual(runtime.state.topicDriftOffer?.topicLabel, "整理 Downloads")

        let result = await runtime.taskStore.splitOffTurn(from: user2.id)
        XCTAssertEqual(result?.newTaskID, runtime.state.activeTaskID)
        XCTAssertEqual(runtime.state.activeTask?.events.map(\.id), [user2.id])
        XCTAssertNil(runtime.state.topicDriftOffer)

        let archived = try await runtime.taskRepository.loadTask(id: originalID)
        XCTAssertEqual(archived?.events.map(\.id), [user1.id, assistant1.id])
    }

    func testApplyThreadOfferStaysOffWhenHistoryIsShort() async throws {
        let runtime = try makeRuntime()
        _ = await runtime.taskStore.createAndActivateTask(relatedTo: [])
        let user = AgentEvent(kind: .userInput, content: "整理 Downloads")
        let didCommit = await runtime.taskStore.commit(appendEvents: [user], deleteEventIDs: [])
        XCTAssertTrue(didCommit)
        runtime.turns.latestUserEventID = user.id
        runtime.turns.applyThreadOffer(from: Self.offerPlan)
        XCTAssertNil(runtime.state.topicDriftOffer)
    }

    func testDismissedThreadOfferStaysSuppressed() async throws {
        let runtime = try makeRuntime()
        let created = await runtime.taskStore.createAndActivateTask(relatedTo: [])
        let originalID = try XCTUnwrap(created)
        let events = [
            AgentEvent(kind: .userInput, content: "整理 Downloads"),
            AgentEvent(kind: .assistantResponse, content: "Sorted."),
            AgentEvent(kind: .userInput, content: "Write a pre-commit hook"),
            AgentEvent(kind: .assistantResponse, content: "Here is a hook."),
        ]
        let didCommit = await runtime.taskStore.commit(appendEvents: events, deleteEventIDs: [])
        XCTAssertTrue(didCommit)
        runtime.turns.latestUserEventID = events[2].id
        runtime.turns.applyThreadOffer(from: Self.offerPlan)
        XCTAssertEqual(runtime.state.topicDriftOffer?.taskID, originalID)

        runtime.dismissTopicDriftOffer()
        XCTAssertNil(runtime.state.topicDriftOffer)
        XCTAssertEqual(runtime.state.suppressedDriftOfferTaskID, originalID)

        runtime.turns.applyThreadOffer(from: Self.offerPlan)
        XCTAssertNil(runtime.state.topicDriftOffer)
    }

    private static let offerPlan = WorkPlan(
        kind: .observe,
        intent: "look at git hooks",
        approach: "Read existing hooks first.",
        threadAdvice: .offerFresh,
        threadLabel: "整理 Downloads"
    )

    private func makeStore() throws -> StoreFixture {
        let directory = try makeTempDirectory()
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
        return StoreFixture(repository: repository, store: store, state: state)
    }

    private func makeRuntime() throws -> AgentRuntime {
        let directory = try makeTempDirectory()
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

    private func makeTempDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SageTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        tempDirectory = directory
        return directory
    }
}

private struct StoreFixture {
    var repository: GRDBTaskRepository
    var store: AgentTaskStore
    var state: AgentSessionState
}
