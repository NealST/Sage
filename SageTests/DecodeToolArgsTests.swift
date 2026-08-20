@testable import Sage
import XCTest

final class DecodeToolArgsTests: XCTestCase {
    private struct LineRangeArgs: Decodable {
        let path: String
        let lineStart: Int?
        let lineEnd: Int?
    }

    private struct ShellArgs: Decodable {
        let command: String
        let workingDirectory: String?
        let timeoutSeconds: Int?
    }

    private struct RenameArgs: Decodable {
        let path: String
        let newName: String
    }

    private struct IncludeHiddenArgs: Decodable {
        let includeHidden: FlexibleBool?
    }

    private struct EventIDArgs: Decodable {
        var fromEventID: String
        var throughEventID: String

        private enum CodingKeys: String, CodingKey {
            case fromEventID = "fromEventId"
            case throughEventID = "throughEventId"
        }
    }

    private struct BrokenEventIDArgs: Decodable {
        var fromEventID: String
        var throughEventID: String
    }

    func testSnakeCaseLineRangeDecodes() throws {
        let args = try decodeToolArgs(
            #"{"path":"README.md","line_start":3,"line_end":5}"#,
            as: LineRangeArgs.self
        )
        XCTAssertEqual(args.path, "README.md")
        XCTAssertEqual(args.lineStart, 3)
        XCTAssertEqual(args.lineEnd, 5)
    }

    func testSnakeCaseShellFieldsDecode() throws {
        let args = try decodeToolArgs(
            #"{"command":"ls","working_directory":"src","timeout_seconds":15}"#,
            as: ShellArgs.self
        )
        XCTAssertEqual(args.command, "ls")
        XCTAssertEqual(args.workingDirectory, "src")
        XCTAssertEqual(args.timeoutSeconds, 15)
    }

    func testSnakeCaseRenameNewNameDecodes() throws {
        let args = try decodeToolArgs(
            #"{"path":"old.txt","new_name":"new.txt"}"#,
            as: RenameArgs.self
        )
        XCTAssertEqual(args.path, "old.txt")
        XCTAssertEqual(args.newName, "new.txt")
    }

    func testFlexibleBoolAcceptsCommonForms() throws {
        let cases: [(String, Bool)] = [
            (#"{"include_hidden":true}"#, true),
            (#"{"include_hidden":false}"#, false),
            (#"{"include_hidden":1}"#, true),
            (#"{"include_hidden":0}"#, false),
            (#"{"include_hidden":"yes"}"#, true),
            (#"{"include_hidden":"n"}"#, false),
        ]
        for (json, expected) in cases {
            let args = try decodeToolArgs(json, as: IncludeHiddenArgs.self)
            XCTAssertEqual(args.includeHidden?.value, expected, json)
        }
    }

    func testEventIDCodingKeysMatchConvertFromSnakeCase() throws {
        let json = #"{"from_event_id":"aaa","through_event_id":"bbb"}"#
        let args = try decodeToolArgs(json, as: EventIDArgs.self)
        XCTAssertEqual(args.fromEventID, "aaa")
        XCTAssertEqual(args.throughEventID, "bbb")
        XCTAssertThrowsError(try decodeToolArgs(json, as: BrokenEventIDArgs.self))
    }

    func testReadTextFileHonorsLineRange() async throws {
        let fixtureRoot = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Caches/SageDecodeArgs-\(UUID().uuidString)",
                isDirectory: true
            )
        let project = fixtureRoot.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        let file = project.appendingPathComponent("notes.txt")
        try "one\ntwo\nthree\nfour\n".write(to: file, atomically: true, encoding: .utf8)
        let root = try PathGuard.validateProjectRoot(project)

        let output = try await PathGuard.$policy.withValue(.project(root: root)) {
            try await ReadTextFileTool().call(
                argumentsJSON: #"{"path":"notes.txt","line_start":2,"line_end":3}"#
            )
        }
        XCTAssertEqual(output, "two\nthree")
    }

    func testModelJSONExtractsFencedAndEmbeddedObjects() {
        XCTAssertEqual(
            (ModelJSON.object(from: "```json\n{\"ok\":true}\n```")?["ok"] as? NSNumber)?.boolValue,
            true
        )
        XCTAssertEqual(
            (ModelJSON.object(from: "prefix {\"n\": 2} suffix")?["n"] as? NSNumber)?.intValue,
            2
        )
        XCTAssertNil(ModelJSON.object(from: "   "))
        XCTAssertNil(ModelJSON.object(from: "no braces here"))
    }

    func testCapToolResultTruncatesOverLimit() {
        let over = String(repeating: "a", count: 50_001)
        let capped = capToolResult(over)
        XCTAssertNotEqual(capped, over)
        XCTAssertTrue(capped.hasPrefix(String(repeating: "a", count: 50_000)))
        XCTAssertTrue(capped.contains("truncated"))
        XCTAssertEqual(capToolResult("short"), "short")
    }
}
