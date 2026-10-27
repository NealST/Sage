@testable import Sage
import XCTest

final class LocalToolCallParserTests: XCTestCase {
    func testHermesBlockYieldsCallAndProse() throws {
        let text = """
        Sure, let me look that up.

        {"name": "get_weather", "arguments": {"city": "Paris"}}

        """
        let parsed = try XCTUnwrap(LocalToolCallParser.parse(text))

        XCTAssertEqual(parsed.prose, "Sure, let me look that up.")
        XCTAssertEqual(parsed.calls.count, 1)
        XCTAssertEqual(parsed.calls[0].name, "get_weather")
        let arguments = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(parsed.calls[0].argumentsJSON.utf8)) as? [String: Any]
        )
        XCTAssertEqual(arguments["city"] as? String, "Paris")
    }

    func testQwen3SectionWithSequentialCalls() throws {
        let text = """
        I will check both.

        <｜tool_calls｜>


        {"name": "read_file", "arguments": {"path": "a.swift"}}


        {"name": "read_file", "arguments": {"path": "b.swift"}}


        """
        let parsed = try XCTUnwrap(LocalToolCallParser.parse(text))

        XCTAssertEqual(parsed.calls.count, 2)
        XCTAssertEqual(parsed.calls[0].name, "read_file")
        XCTAssertEqual(parsed.calls[1].name, "read_file")
        XCTAssertTrue(parsed.calls[0].id.hasPrefix("local_"))
        XCTAssertTrue(parsed.calls[0].id != parsed.calls[1].id)
    }

    func testQwen2LegacyParametersKey() throws {
        let text = "\n{\"name\": \"run_tests\", \"parameters\": {\"scope\": \"all\"}}\n"
        let parsed = try XCTUnwrap(LocalToolCallParser.parse(text))

        XCTAssertEqual(parsed.calls.count, 1)
        XCTAssertEqual(parsed.calls[0].name, "run_tests")
        XCTAssertTrue(parsed.calls[0].argumentsJSON.contains("all"))
    }

    func testArgumentsAsStringIsPreservedWhenValidJSON() throws {
        let text = "\n{\"name\": \"write_file\", \"arguments\": \"{\\\"path\\\": \\\"x\\\"}\"}\n"
        let parsed = try XCTUnwrap(LocalToolCallParser.parse(text))

        let arguments = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(parsed.calls[0].argumentsJSON.utf8)) as? [String: Any]
        )
        XCTAssertEqual(arguments["path"] as? String, "x")
    }

    func testNoMarkersReturnsNil() {
        XCTAssertNil(LocalToolCallParser.parse("Just a plain answer, no tools here."))
    }

    func testVisibleTextStopsAtMarker() {
        let text = "Answer text <｜tool_calls｜>\n{\"name\": \"x\"}"
        XCTAssertEqual(LocalToolCallParser.visibleText(in: text), "Answer text")
    }

    // MARK: - Streaming filter

    func testStreamFilterHoldsBackPartialMarker() {
        var filter = LocalToolCallStreamFilter()

        let first = filter.push("Hello <tool_c")
        XCTAssertEqual(first, "Hello ")
        XCTAssertNil(filter.push("alls_begin>{\"name\": \"a\"}"))
        let finalized = filter.finalize()

        XCTAssertEqual(finalized.prose, "Hello")
        XCTAssertEqual(finalized.calls.count, 1)
        XCTAssertEqual(finalized.calls[0].name, "a")
    }

    func testStreamFilterPassesPlainTextThrough() {
        var filter = LocalToolCallStreamFilter()

        XCTAssertNil(filter.push(""))
        XCTAssertEqual(filter.push("just text"), "just text")
        let finalized = filter.finalize()

        XCTAssertEqual(finalized.prose, "just text")
        XCTAssertTrue(finalized.calls.isEmpty)
    }

    func testStreamFilterSuppressesAfterCompleteMarker() {
        var filter = LocalToolCallStreamFilter()

        XCTAssertEqual(filter.push("before "), "before ")
        XCTAssertNil(filter.push(" {\"name\": \"f\"} more text"))
        let finalized = filter.finalize()

        XCTAssertEqual(finalized.prose, "before")
        XCTAssertEqual(finalized.calls.count, 1)
        XCTAssertEqual(finalized.calls[0].name, "f")
    }
}
