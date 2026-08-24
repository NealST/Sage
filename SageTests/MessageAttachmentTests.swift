@testable import Sage
import XCTest

final class MessageAttachmentTests: XCTestCase {
    func testEventDecodesWithoutAttachments() throws {
        let event = AgentEvent(kind: .userInput, content: "hello")
        let encoded = try JSONEncoder().encode(event)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "attachments")
        let stripped = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(AgentEvent.self, from: stripped)
        XCTAssertEqual(decoded.content, "hello")
        XCTAssertTrue(decoded.attachments.isEmpty)
    }

    func testModelFacingListingAndSubmitQuery() {
        let shot = MessageAttachment(
            kind: .image,
            displayName: "shot.png",
            path: "/Users/test/Desktop/shot.png"
        )
        let file = MessageAttachment(
            kind: .file,
            displayName: "App.swift",
            path: "/Users/test/src/App.swift"
        )
        let event = AgentEvent(
            kind: .userInput,
            content: "fix this",
            attachments: [shot, file]
        )
        let current = event.modelFacingContent(includeImagePixels: true)
        XCTAssertTrue(current.contains("fix this"))
        XCTAssertTrue(current.contains("Attached:"))
        XCTAssertTrue(current.contains("(image)"))
        XCTAssertTrue(current.contains("(file)"))

        let historical = event.modelFacingContent(includeImagePixels: false)
        XCTAssertTrue(historical.contains("[image: shot.png]"))
        XCTAssertFalse(historical.contains("(image)"))

        XCTAssertEqual(
            MessageAttachment.submitQuery(text: "", attachments: [shot, file]),
            "Attached shot.png, App.swift"
        )
        XCTAssertEqual(
            MessageAttachment.submitQuery(text: "look", attachments: [shot]),
            "look"
        )
    }

    func testTopicFromAttachmentOnlyTurn() {
        let shot = MessageAttachment(
            kind: .image,
            displayName: "shot.png",
            path: "/Users/test/Desktop/shot.png"
        )
        let event = AgentEvent(kind: .userInput, content: "", attachments: [shot])
        let topic = TopicGenerator.generate(from: [event])
        XCTAssertEqual(topic?.topic.isEmpty, false)
        XCTAssertTrue(topic?.abstract.contains("shot.png") == true)
    }

    func testResolveRejectsPathsOutsideHomeAndCapsCount() throws {
        let outside = AttachmentImport.resolve(
            [URL(fileURLWithPath: "/tmp")],
            into: []
        )
        XCTAssertTrue(outside.attachments.isEmpty)
        XCTAssertEqual(outside.hint, AttachmentImport.outsideHomeHint)

        let homeFile = try makeHomeFile(name: "sage-attachment-test.txt")
        defer { try? FileManager.default.removeItem(at: homeFile) }

        var existing: [MessageAttachment] = []
        for index in 0..<MessageAttachment.maxCount {
            existing.append(
                MessageAttachment(
                    kind: .file,
                    displayName: "keep-\(index).txt",
                    path: "/Users/test/keep-\(index).txt"
                )
            )
        }
        let capped = AttachmentImport.resolve([homeFile], into: existing)
        XCTAssertEqual(capped.attachments.count, MessageAttachment.maxCount)
        XCTAssertEqual(capped.hint, AttachmentImport.tooManyHint)

        let added = AttachmentImport.resolve([homeFile], into: [])
        XCTAssertEqual(added.attachments.count, 1)
        XCTAssertEqual(added.attachments[0].kind, .file)
        XCTAssertEqual(added.attachments[0].path, homeFile.path)
        XCTAssertNil(added.hint)
    }

    func testReadAllowlistUsesResolvedPaths() {
        let file = MessageAttachment(
            kind: .file,
            displayName: "App.swift",
            path: NSHomeDirectory() + "/src/App.swift"
        )
        let event = AgentEvent(kind: .userInput, content: "", attachments: [file])
        let allow = MessageAttachment.readAllowlist(from: [event])
        XCTAssertEqual(allow.count, 1)
        XCTAssertTrue(allow[0].hasSuffix("/src/App.swift") || allow[0].contains("App.swift"))
    }

    func testAPIMessageKeepsStringContentWithoutImages() throws {
        let event = AgentEvent(kind: .userInput, content: "hello")
        let message = APIMessage(event)
        let data = try JSONEncoder().encode(message)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(object?["role"] as? String, "user")
        XCTAssertEqual(object?["content"] as? String, "hello")
    }

    func testPersistsAttachmentsOnUserEvent() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SageTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let repository = GRDBTaskRepository(
            databaseURL: directory.appendingPathComponent("sage.sqlite"),
            legacyJSONURL: directory.appendingPathComponent("tasks.json")
        )
        let homeFile = try makeHomeFile(name: "sage-attachment-persist.txt")
        defer { try? FileManager.default.removeItem(at: homeFile) }

        let attachment = MessageAttachment(
            kind: .file,
            displayName: homeFile.lastPathComponent,
            path: homeFile.path
        )
        let task = TaskRecord()
        try await repository.saveTaskState(task, setActive: true)
        try await repository.mutateTask(
            task,
            appendEvents: [
                AgentEvent(kind: .userInput, content: "see this", attachments: [attachment]),
            ],
            deleteEventIDs: [],
            setActive: true
        )

        let loaded = try await repository.loadTask(id: task.id)
        let stored = loaded?.events.first?.attachments ?? []
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.first?.path, homeFile.path)
        XCTAssertEqual(stored.first?.kind, .file)
    }

    private func makeHomeFile(name: String) throws -> URL {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/SageAttachmentTests", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try "hello".write(to: url, atomically: true, encoding: .utf8)
        return url.resolvingSymlinksInPath().standardizedFileURL
    }
}
