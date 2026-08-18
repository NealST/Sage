import XCTest
@testable import Sage

final class TaskWorkingMemoryTests: XCTestCase {
    func testStructuredPromptAppendixListsFilledSectionsOnly() {
        let from = UUID()
        let through = UUID()
        let memory = TaskWorkingMemory.makeStructured(
            foldedFromEventID: from,
            foldedThroughEventID: through,
            overview: "Clean Downloads",
            focus: "Last listed ~/Downloads",
            nextSteps: "Delete installers after confirm"
        )

        let appendix = memory.promptAppendix
        XCTAssertTrue(appendix.contains("## Working memory"))
        XCTAssertTrue(appendix.contains(from.uuidString))
        XCTAssertTrue(appendix.contains(through.uuidString))
        XCTAssertTrue(appendix.contains("Overview: Clean Downloads"))
        XCTAssertTrue(appendix.contains("Focus: Last listed ~/Downloads"))
        XCTAssertTrue(appendix.contains("Next steps: Delete installers after confirm"))
        XCTAssertTrue(appendix.contains("recall_task_transcript"))
        XCTAssertFalse(appendix.contains("Architecture:"))
        XCTAssertFalse(appendix.contains("Recents"))
    }

    func testSimplePromptAppendixUsesNarrative() {
        let memory = TaskWorkingMemory.makeSimple(
            foldedFromEventID: UUID(),
            foldedThroughEventID: UUID(),
            narrative: "User asked to tidy Downloads; listed files; waiting to delete."
        )
        XCTAssertEqual(memory.mode, .simple)
        XCTAssertTrue(memory.promptAppendix.contains("User asked to tidy Downloads"))
        XCTAssertFalse(memory.promptAppendix.contains("Overview:"))
    }

    func testEmptySnapshotHasNoPromptAppendix() {
        let memory = TaskWorkingMemory(
            foldedFromEventID: UUID(),
            foldedThroughEventID: UUID(),
            mode: .structured
        )
        XCTAssertFalse(memory.hasContent)
        XCTAssertEqual(memory.promptAppendix, "")
    }

    func testValidatedKeepsSnapshotWhenSpanIsIntact() {
        let first = AgentEvent(kind: .userInput, content: "one")
        let second = AgentEvent(kind: .assistantResponse, content: "two")
        let third = AgentEvent(kind: .userInput, content: "three")
        let memory = TaskWorkingMemory.makeSimple(
            foldedFromEventID: first.id,
            foldedThroughEventID: second.id,
            narrative: "fold"
        )

        XCTAssertEqual(
            memory.validated(against: [first, second, third])?.id,
            memory.id
        )
        XCTAssertEqual(memory.foldedEventIDs(in: [first, second, third]), [first.id, second.id])
    }

    func testValidatedDropsSnapshotWhenAnEndpointIsMissing() {
        let first = AgentEvent(kind: .userInput, content: "one")
        let second = AgentEvent(kind: .assistantResponse, content: "two")
        let memory = TaskWorkingMemory.makeSimple(
            foldedFromEventID: first.id,
            foldedThroughEventID: second.id,
            narrative: "fold"
        )

        XCTAssertNil(memory.validated(against: [second]))
        XCTAssertEqual(memory.foldedEventIDs(in: [second]), [])
    }

    func testValidatedLeavesSnapshotAloneWhenHistoryIsUnknown() {
        let memory = TaskWorkingMemory.makeSimple(
            foldedFromEventID: UUID(),
            foldedThroughEventID: UUID(),
            narrative: "fold"
        )
        XCTAssertEqual(memory.validated(against: [])?.id, memory.id)
    }

    func testRoundTripsThroughTaskPersistence() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SageTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let repository = GRDBTaskRepository(
            databaseURL: directory.appendingPathComponent("sage.sqlite"),
            legacyJSONURL: directory.appendingPathComponent("tasks.json")
        )
        let from = UUID()
        let through = UUID()
        var task = TaskRecord(
            workingMemory: .makeStructured(
                foldedFromEventID: from,
                foldedThroughEventID: through,
                sourceModel: "test-model",
                overview: "Clean Downloads",
                nextSteps: "Ask before deleting"
            )
        )
        try await repository.saveTaskState(task, setActive: true)

        let loaded = try await repository.loadTask(id: task.id)
        XCTAssertEqual(loaded?.workingMemory?.mode, .structured)
        XCTAssertEqual(loaded?.workingMemory?.foldedFromEventID, from)
        XCTAssertEqual(loaded?.workingMemory?.foldedThroughEventID, through)
        XCTAssertEqual(loaded?.workingMemory?.overview, "Clean Downloads")
        XCTAssertEqual(loaded?.workingMemory?.nextSteps, "Ask before deleting")
        XCTAssertEqual(loaded?.workingMemory?.sourceModel, "test-model")

        let metadata = try await repository.loadTaskMetadata(id: task.id)
        XCTAssertEqual(metadata?.workingMemory?.overview, "Clean Downloads")
        XCTAssertTrue(metadata?.events.isEmpty == true)

        task.workingMemory = nil
        try await repository.saveTaskState(task, setActive: false)
        XCTAssertNil(try await repository.loadTask(id: task.id)?.workingMemory)
    }

    func testDoesNotPersistAnEmptySnapshot() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SageTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let repository = GRDBTaskRepository(
            databaseURL: directory.appendingPathComponent("sage.sqlite"),
            legacyJSONURL: directory.appendingPathComponent("tasks.json")
        )
        let task = TaskRecord(
            workingMemory: TaskWorkingMemory(
                foldedFromEventID: UUID(),
                foldedThroughEventID: UUID(),
                mode: .structured
            )
        )
        try await repository.saveTaskState(task, setActive: true)
        XCTAssertNil(try await repository.loadTask(id: task.id)?.workingMemory)
    }

    func testUpdateWorkingMemoryDoesNotRewriteEvents() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SageTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let repository = GRDBTaskRepository(
            databaseURL: directory.appendingPathComponent("sage.sqlite"),
            legacyJSONURL: directory.appendingPathComponent("tasks.json")
        )
        let user = AgentEvent(kind: .userInput, content: "clean downloads")
        let assistant = AgentEvent(kind: .assistantResponse, content: "listed files")
        let task = TaskRecord(events: [user, assistant])
        try await repository.mutateTask(
            task,
            appendEvents: [user, assistant],
            deleteEventIDs: [],
            setActive: true
        )

        let memory = TaskWorkingMemory.makeSimple(
            foldedFromEventID: user.id,
            foldedThroughEventID: assistant.id,
            narrative: "fold"
        )
        try await repository.updateWorkingMemory(taskID: task.id, memory: memory)

        let loaded = try await repository.loadTask(id: task.id)
        XCTAssertEqual(loaded?.workingMemory?.narrative, "fold")
        XCTAssertEqual(loaded?.events.map(\.id), [user.id, assistant.id])
    }
}
