@testable import Sage
import XCTest

final class WorkspaceChangeBookTests: XCTestCase {
    func testTwoWritesToSameFileFoldToNet() {
        var book = WorkspaceChangeBook()
        book.applyWrite(path: "a.swift", before: "one\n", after: "one\ntwo\n", created: false)
        book.applyWrite(path: "a.swift", before: "one\ntwo\n", after: "three\n", created: false)
        let files = book.snapshot().files
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files[0].kind, .modified)
        XCTAssertEqual(files[0].before, "one\n")
        XCTAssertEqual(files[0].after, "three\n")
    }

    func testCreateThenDeleteDropsFromSnapshot() {
        var book = WorkspaceChangeBook()
        book.applyWrite(path: "tmp.txt", before: nil, after: "hi\n", created: true)
        book.applyDelete(path: "tmp.txt")
        XCTAssertTrue(book.snapshot().files.isEmpty)
    }

    func testWriteThenRestoreBaselineDropsFromSnapshot() {
        var book = WorkspaceChangeBook()
        book.applyWrite(path: "a.swift", before: "keep\n", after: "changed\n", created: false)
        book.applyWrite(path: "a.swift", before: "changed\n", after: "keep\n", created: false)
        XCTAssertTrue(book.snapshot().files.isEmpty)
    }

    func testReviewBriefOmitsToolTrace() {
        var book = WorkspaceChangeBook()
        book.applyWrite(path: "README.md", before: nil, after: "# Hello\n", created: true)
        book.markOpaque()
        let brief = book.snapshot().reviewBrief(maxChars: 2_000)
        XCTAssertTrue(brief.contains("README.md"))
        XCTAssertTrue(brief.contains("added"))
        XCTAssertTrue(brief.contains("Non-file actions completed"))
        XCTAssertFalse(brief.contains("Tool result"))
        XCTAssertFalse(brief.contains("write_text_file"))
    }

    func testEventDecodesWithoutWorkspaceChanges() throws {
        let event = AgentEvent(kind: .assistantResponse, content: "done")
        let encoded = try JSONEncoder().encode(event)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "workspaceChanges")
        let stripped = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(AgentEvent.self, from: stripped)
        XCTAssertNil(decoded.workspaceChanges)
        XCTAssertEqual(decoded.content, "done")
    }

    func testRecordingWritePayload() {
        var book = WorkspaceChangeBook()
        let result = WriteFileResultCodec.makeResult(
            path: "note.txt",
            created: true,
            before: nil,
            after: "hello\n"
        )
        TurnChangeSetRecording.apply(
            toolName: "write_text_file",
            argumentsJSON: #"{"path":"note.txt","content":"hello\n"}"#,
            result: result,
            to: &book
        )
        XCTAssertEqual(book.snapshot().files.first?.kind, .added)
        XCTAssertEqual(book.snapshot().files.first?.after, "hello\n")
    }

    func testRecordingClipboardCountsAsNonFileAction() {
        var book = WorkspaceChangeBook()
        TurnChangeSetRecording.apply(
            toolName: "set_clipboard",
            argumentsJSON: #"{"text":"hello"}"#,
            result: "[OK] Clipboard updated",
            to: &book
        )
        let snapshot = book.snapshot()
        XCTAssertTrue(snapshot.files.isEmpty)
        XCTAssertEqual(snapshot.actions, [WorkspaceAction(toolName: "set_clipboard", succeeded: true)])
        XCTAssertFalse(snapshot.isEmpty)
        let brief = snapshot.reviewBrief(maxChars: 2_000)
        XCTAssertTrue(brief.contains("No files changed."))
        XCTAssertTrue(brief.contains("set_clipboard (completed)"))
        XCTAssertFalse(brief.contains("No workspace files changed."))
        XCTAssertEqual(snapshot.inspectPlaces(), ["clipboard"])
    }

    func testInspectPlacesListsPathsWithoutBodies() {
        var book = WorkspaceChangeBook()
        book.applyWrite(path: "Install.md", before: nil, after: "## Install\n", created: true)
        let places = book.snapshot().inspectPlaces()
        XCTAssertEqual(places, ["Install.md"])
        XCTAssertFalse(places.contains { $0.contains("## Install") })
    }

    func testRecordingReadDoesNotCountAsEvidence() {
        var book = WorkspaceChangeBook()
        TurnChangeSetRecording.apply(
            toolName: "get_clipboard",
            argumentsJSON: "{}",
            result: "hello",
            to: &book
        )
        XCTAssertTrue(book.snapshot().isEmpty)
        XCTAssertTrue(book.snapshot().actions.isEmpty)
    }

    func testDecodingLegacyChangeSetWithoutActions() throws {
        let legacy = WorkspaceChangeSet(files: [], opaqueMutationCount: 2)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as? [String: Any]
        )
        object.removeValue(forKey: "actions")
        let decoded = try JSONDecoder().decode(
            WorkspaceChangeSet.self,
            from: try JSONSerialization.data(withJSONObject: object)
        )
        XCTAssertEqual(decoded.opaqueMutationCount, 2)
        XCTAssertTrue(decoded.actions.isEmpty)
    }

    func testRecordingFailedNotifyStillCountsAsEvidence() {
        var book = WorkspaceChangeBook()
        TurnChangeSetRecording.apply(
            toolName: "notify",
            argumentsJSON: #"{"title":"Hi"}"#,
            result: "denied",
            succeeded: false,
            to: &book
        )
        XCTAssertEqual(book.snapshot().actions.first?.succeeded, false)
        XCTAssertFalse(book.snapshot().isEmpty)
    }
}
