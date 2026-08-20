@testable import Sage
import XCTest

final class ReviewAgentTests: XCTestCase {
    func testParsesRevise() {
        let verdict = ReviewAgent.parse("""
        {"decision":"revise","feedback":"README 里还没有安装步骤"}
        """)
        XCTAssertEqual(verdict?.decision, .revise)
        XCTAssertEqual(verdict?.feedback, "README 里还没有安装步骤")
    }

    func testParsesAcceptInFence() {
        let verdict = ReviewAgent.parse("""
        ```json
        {"decision":"accept","feedback":"意图已覆盖"}
        ```
        """)
        XCTAssertEqual(verdict?.decision, .accept)
    }

    func testDigestKeepsUserAndTools() {
        let events = [
            AgentEvent(kind: .userInput, content: "补一下安装说明"),
            AgentEvent(
                kind: .assistantResponse,
                content: "",
                toolCalls: [ToolCallRecord(id: "1", name: "read_text_file", argumentsJSON: "{}")]
            ),
            AgentEvent(kind: .toolResult, content: "# VineNote"),
        ]
        let digest = TranscriptDigest.make(from: events)
        XCTAssertTrue(digest.contains("User:"))
        XCTAssertTrue(digest.contains("read_text_file"))
        XCTAssertTrue(digest.contains("VineNote"))
    }
}
