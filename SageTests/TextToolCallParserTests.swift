@testable import Sage
import XCTest

final class TextToolCallParserTests: XCTestCase {
    private let leaked = """
        <｜｜DSML｜tool_calls> <｜｜DSML｜invoke name="read_file"> \
        <｜｜DSML｜parameter name="path" string="true">README.zh-CN.md</｜｜DSML｜parameter> \
        </｜｜DSML｜invoke> </｜｜DSML｜tool_calls>
        """

    func testRecoversDSMLReadFileAsReadTextFile() {
        let parsed = TextToolCallParser.parse(leaked)
        XCTAssertNotNil(parsed)
        XCTAssertNil(parsed?.prose)
        XCTAssertEqual(parsed?.calls.count, 1)
        XCTAssertEqual(parsed?.calls.first?.name, "read_text_file")
        XCTAssertEqual(parsed?.calls.first?.argumentsJSON, #"{"path":"README.zh-CN.md"}"#)
    }

    func testKeepsLeadingProseAndHidesMarkupWhileStreaming() {
        let buffer = "先看一下说明\n\(leaked)"
        XCTAssertEqual(TextToolCallParser.visibleText(in: buffer), "先看一下说明")

        let parsed = TextToolCallParser.parse(buffer)
        XCTAssertEqual(parsed?.prose, "先看一下说明")
        XCTAssertEqual(parsed?.calls.first?.name, "read_text_file")
    }

    func testLeavesOrdinaryRepliesAlone() {
        let text = "README.zh-CN.md 是项目说明。"
        XCTAssertNil(TextToolCallParser.parse(text))
        XCTAssertEqual(TextToolCallParser.visibleText(in: text), text)

        let recovered = TextToolCallParser.recover(from: text, existing: [])
        XCTAssertEqual(recovered.content, text)
        XCTAssertTrue(recovered.calls.isEmpty)
    }

    func testDoesNotOverrideStructuredToolCalls() {
        let existing = [
            ToolCallProposal(id: "call_1", name: "read_text_file", argumentsJSON: #"{"path":"A.md"}"#)
        ]
        let recovered = TextToolCallParser.recover(from: leaked, existing: existing)
        XCTAssertEqual(recovered.calls, existing)
        XCTAssertNil(recovered.content)
    }
}
