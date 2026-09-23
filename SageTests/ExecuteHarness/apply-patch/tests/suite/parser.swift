@testable import ApplyPatch
@testable import Sage
import XCTest

final class ApplyPatchParserTests: XCTestCase {
    func testRejectsMissingBeginMarker() {
        XCTAssertEqual(
            parseError("bad"),
            .invalidPatch("The first line of the patch must be '*** Begin Patch'")
        )
    }

    func testRejectsMissingEndMarker() {
        XCTAssertEqual(
            parseError("*** Begin Patch\nbad"),
            .invalidPatch("The last line of the patch must be '*** End Patch'")
        )
    }

    func testParsesAddDeleteUpdateAndMove() throws {
        let hunks = try parsePatchText(
            """
            *** Begin Patch
            *** Add File: path/add.py
            +abc
            +def
            *** Delete File: path/delete.py
            *** Update File: path/update.py
            *** Move to: path/update2.py
            @@ def f():
            -    pass
            +    return 123
            *** End Patch
            """,
            mode: .strict
        ).hunks
        XCTAssertEqual(
            hunks,
            [
                .addFile(path: "path/add.py", contents: "abc\ndef\n"),
                .deleteFile(path: "path/delete.py"),
                .updateFile(
                    path: "path/update.py",
                    movePath: "path/update2.py",
                    chunks: [
                        UpdateFileChunk(
                            changeContext: "def f():",
                            oldLines: ["    pass"],
                            newLines: ["    return 123"]
                        ),
                    ]
                ),
            ]
        )
    }

    func testEmptyUpdateHunkIsRejected() {
        XCTAssertEqual(
            parseError(
                """
                *** Begin Patch
                *** Update File: test.py
                *** End Patch
                """
            ),
            .invalidHunk(message: "Update file hunk for path 'test.py' is empty", lineNumber: 2)
        )
    }

    func testEmptyPatchHasNoHunks() throws {
        let hunks = try parsePatch(
            """
            *** Begin Patch
            *** End Patch
            """
        ).hunks
        XCTAssertTrue(hunks.isEmpty)
    }

    func testLenientHeredocUnwrapsPatch() throws {
        let body = """
        *** Begin Patch
        *** Update File: file2.py
         import foo
        +bar
        *** End Patch
        """
        let expected = [
            Hunk.updateFile(
                path: "file2.py",
                movePath: nil,
                chunks: [
                    UpdateFileChunk(
                        changeContext: nil,
                        oldLines: ["import foo"],
                        newLines: ["import foo", "bar"],
                        contextLineIndices: [(0, 0)]
                    ),
                ]
            ),
        ]
        XCTAssertThrowsError(try parsePatchText("<<EOF\n\(body)\nEOF\n", mode: .strict))
        XCTAssertEqual(try parsePatchText("<<EOF\n\(body)\nEOF\n", mode: .lenient).hunks, expected)
        XCTAssertEqual(try parsePatchText("<<'EOF'\n\(body)\nEOF\n", mode: .lenient).hunks, expected)
    }

    func testEnvironmentIDPreamble() throws {
        let parsed = try parsePatchText(
            """
            *** Begin Patch
            *** Environment ID: remote
            *** Add File: hello.txt
            +hello
            *** End Patch
            """,
            mode: .strict
        )
        XCTAssertEqual(parsed.environmentID, "remote")
        XCTAssertEqual(parsed.hunks, [.addFile(path: "hello.txt", contents: "hello\n")])
    }

    func testEmptyEnvironmentIDIsRejected() {
        XCTAssertEqual(
            parseError(
                """
                *** Begin Patch
                *** Environment ID:   
                *** Add File: hello.txt
                +hello
                *** End Patch
                """
            ),
            .invalidPatch("apply_patch environment_id cannot be empty")
        )
    }

    private func parseError(_ patch: String) -> ParseError? {
        do {
            _ = try parsePatch(patch)
            return nil
        } catch let error as ParseError {
            return error
        } catch {
            return nil
        }
    }
}
