@testable import Sage
import XCTest

final class ApplyPatchToolTests: XCTestCase {
    func testToolAppliesHunksInsideAProjectRoot() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try "foo\nbar\n".write(to: root.appendingPathComponent("note.txt"), atomically: true, encoding: .utf8)

        let result = try PathGuard.$policy.withValue(.project(root: root)) {
            try ApplyPatchHandler().call(
                argumentsJSON: Self.json(
                    """
                    *** Begin Patch
                    *** Update File: note.txt
                    @@
                     foo
                    -bar
                    +baz
                    *** End Patch
                    """
                )
            )
        }

        XCTAssertTrue(result.contains("M note.txt"))
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("note.txt")), "foo\nbaz\n")
        let payloads = WriteFileResultCodec.payloads(in: result)
        XCTAssertEqual(payloads.count, 1)
        XCTAssertEqual(payloads.first?.before, "foo\nbar\n")
        XCTAssertEqual(payloads.first?.after, "foo\nbaz\n")
    }

    func testContextMismatchLeavesTheFileUnchanged() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try "keep\n".write(to: root.appendingPathComponent("note.txt"), atomically: true, encoding: .utf8)

        XCTAssertThrowsError(
            try PathGuard.$policy.withValue(.project(root: root)) {
                try ApplyPatchHandler().call(
                    argumentsJSON: Self.json(
                        """
                        *** Begin Patch
                        *** Update File: note.txt
                        @@
                        -missing
                        +changed
                        *** End Patch
                        """
                    )
                )
            }
        )
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("note.txt")), "keep\n")
    }

    func testObservePlanRejectsApplyPatch() {
        XCTAssertThrowsError(
            try ToolInvocationDispatcher.assertMutatingToolsAllowed(
                for: ApplyPatchSpec.toolName,
                workPlanKind: .observe
            )
        )
    }

    func testWorkspaceChangeSetRecordsHunks() throws {
        let result = WriteFileResultCodec.embed(
            summary: "Success. Updated the following files:\nM README.md",
            payloads: [
                WriteFileDiffPayload(
                    path: "README.md",
                    created: false,
                    before: "old\n",
                    after: "new\n",
                    insertions: 1,
                    deletions: 1,
                    truncated: false
                ),
            ]
        )
        var book = WorkspaceChangeBook()
        TurnChangeSetRecording.apply(
            toolName: "apply_patch",
            argumentsJSON: "{}",
            result: result,
            to: &book
        )
        XCTAssertEqual(book.snapshot().files.first?.path, "README.md")
        XCTAssertEqual(book.snapshot().files.first?.kind, .modified)
        XCTAssertEqual(book.snapshot().files.first?.after, "new\n")
    }

    private func makeRoot() throws -> URL {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/SageApplyPatchTests/\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private static func json(_ patch: String) -> String {
        let data = try! JSONSerialization.data(withJSONObject: ["input": patch])
        return String(data: data, encoding: .utf8)!
    }
}
