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

    func testBriefKeepsTheFullExecuteReply() {
        let draft = String(repeating: "x", count: 2_000)
        let brief = ReviewAgent.brief(
            userText: "补安装说明",
            plan: nil,
            draft: draft,
            turnDigest: "Tool result: wrote Install.md",
            changes: .empty
        )
        XCTAssertTrue(brief.contains(draft))
        XCTAssertTrue(brief.contains("补安装说明"))
        XCTAssertTrue(brief.contains("wrote Install.md"))
    }

    func testChangeSetBriefIsTheReviewEvidence() {
        var book = WorkspaceChangeBook()
        book.applyWrite(path: "Install.md", before: nil, after: "## Install\n", created: true)
        let brief = book.snapshot().reviewBrief(maxChars: 1_000)
        XCTAssertTrue(brief.contains("Install.md"))
        XCTAssertFalse(brief.contains("read_text_file"))
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
