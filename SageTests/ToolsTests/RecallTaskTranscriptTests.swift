@testable import Sage
import XCTest

final class RecallTaskTranscriptTests: XCTestCase {
    func testRejectsNonUUIDArguments() async {
        do {
            _ = try await RecallTaskTranscriptTool.execute(
                argumentsJSON: #"{"from_event_id":"nope","through_event_id":"also-nope"}"#
            )
            XCTFail("expected invalid arguments")
        } catch ToolError.invalidArguments(let detail) {
            XCTAssertTrue(detail.contains("UUID"))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testRequiresActiveTaskContext() async throws {
        let from = UUID()
        let through = UUID()
        do {
            _ = try await RecallTaskTranscriptTool.execute(
                argumentsJSON: json(from: from, through: through)
            )
            XCTFail("expected missing context")
        } catch ToolError.operationFailed(let detail) {
            XCTAssertTrue(detail.contains("unavailable"))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testReadsOnlyTheCurrentTaskAndSwapsAReversedRange() async throws {
        let (repository, directory) = try makeRepository()
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = AgentEvent(kind: .userInput, content: "clean downloads")
        let second = AgentEvent(kind: .assistantResponse, content: "listed files")
        let third = AgentEvent(kind: .userInput, content: "delete installers")
        let task = TaskRecord(events: [first, second, third])
        try await repository.mutateTask(
            task,
            appendEvents: [first, second, third],
            deleteEventIDs: [],
            setActive: true
        )

        let other = AgentEvent(kind: .userInput, content: "secret from another task")
        let otherTask = TaskRecord(events: [other])
        try await repository.mutateTask(
            otherTask,
            appendEvents: [other],
            deleteEventIDs: [],
            setActive: false
        )

        let output = try await ActiveTaskContext.$repository.withValue(repository) {
            try await ActiveTaskContext.$taskID.withValue(task.id) {
                try await RecallTaskTranscriptTool.execute(
                    argumentsJSON: json(from: third.id, through: first.id)
                )
            }
        }
        XCTAssertTrue(output.contains(first.id.uuidString))
        XCTAssertTrue(output.contains("clean downloads"))
        XCTAssertTrue(output.contains("listed files"))
        XCTAssertTrue(output.contains("delete installers"))
        XCTAssertFalse(output.contains("secret from another task"))

        do {
            _ = try await ActiveTaskContext.$repository.withValue(repository) {
                try await ActiveTaskContext.$taskID.withValue(task.id) {
                    try await RecallTaskTranscriptTool.execute(
                        argumentsJSON: json(from: other.id, through: other.id)
                    )
                }
            }
            XCTFail("expected unknown event IDs")
        } catch ToolError.operationFailed(let detail) {
            XCTAssertTrue(detail.contains("not on the current task"))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testCapsOversizedRecallWithMiddleOut() async throws {
        let (repository, directory) = try makeRepository()
        defer { try? FileManager.default.removeItem(at: directory) }

        let events = (0..<8).map { index in
            AgentEvent(
                kind: .userInput,
                content: String(repeating: "E\(index)", count: 1_000)
            )
        }
        let task = TaskRecord(events: events)
        try await repository.mutateTask(
            task,
            appendEvents: events,
            deleteEventIDs: [],
            setActive: true
        )

        let output = try await ActiveTaskContext.$repository.withValue(repository) {
            try await ActiveTaskContext.$taskID.withValue(task.id) {
                try await RecallTaskTranscriptTool.execute(
                    argumentsJSON: json(
                        from: try XCTUnwrap(events.first).id,
                        through: try XCTUnwrap(events.last).id
                    )
                )
            }
        }
        XCTAssertTrue(output.contains("recall truncated"))
        XCTAssertLessThanOrEqual(
            output.utf8.count,
            RecallTaskTranscriptTool.maxOutputCharacters + 200
        )
    }

    func testHumanTitleIsStable() {
        XCTAssertEqual(
            ToolCallPresentation.humanTitle(
                name: RecallTaskTranscriptTool.name,
                argumentsJSON: json(from: UUID(), through: UUID())
            ),
            "Recall earlier turns"
        )
    }

    private func json(from: UUID, through: UUID) -> String {
        """
        {"from_event_id":"\(from.uuidString)","through_event_id":"\(through.uuidString)"}
        """
    }

    private func makeRepository() throws -> (GRDBTaskRepository, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SageTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let repository = GRDBTaskRepository(
            databaseURL: directory.appendingPathComponent("sage.sqlite"),
            legacyJSONURL: directory.appendingPathComponent("tasks.json")
        )
        return (repository, directory)
    }
}
