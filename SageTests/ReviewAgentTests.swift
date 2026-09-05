@testable import Sage
import XCTest

final class ReviewAgentTests: XCTestCase {
    func testParsesReviseAsMustFix() {
        let verdict = ReviewAgent.parse("""
        {"decision":"revise","feedback":"README 里还没有安装步骤"}
        """)
        XCTAssertEqual(verdict?.mustFix, "README 里还没有安装步骤")
        XCTAssertNil(verdict?.optional)
        XCTAssertTrue(verdict?.hasMustFix == true)
    }

    func testParsesAcceptInFence() {
        let verdict = ReviewAgent.parse("""
        ```json
        {"decision":"accept","feedback":"意图已覆盖"}
        ```
        """)
        XCTAssertNil(verdict?.mustFix)
        XCTAssertNil(verdict?.optional)
        XCTAssertFalse(verdict?.hasMustFix == true)
    }

    func testParsesEmptyFieldsAsNoFindings() {
        let verdict = ReviewAgent.parse(#"{"must_fix":"","optional":"  "}"#)
        XCTAssertNil(verdict?.mustFix)
        XCTAssertNil(verdict?.optional)
        XCTAssertFalse(verdict?.hasMustFix == true)
        XCTAssertFalse(verdict?.hasOptional == true)
    }

    func testParsesMustFixAndOptional() {
        let verdict = ReviewAgent.parse("""
        {"must_fix":"安装步骤还缺 brew","optional":"目录名可以更短"}
        """)
        XCTAssertEqual(verdict?.mustFix, "安装步骤还缺 brew")
        XCTAssertEqual(verdict?.optional, "目录名可以更短")
    }

    func testBriefIsContractDraftAndSandbox() {
        let brief = ReviewAgent.brief(
            userText: "补安装说明",
            workPlan: WorkPlan(
                kind: .act,
                intent: "补安装说明",
                approach: "只改 Install.md。",
                sideEffects: "会改文件"
            ),
            draft: "已经补上安装步骤。",
            sandbox: "This project"
        )
        XCTAssertTrue(brief.contains("补安装说明"))
        XCTAssertTrue(brief.contains("Install.md"))
        XCTAssertTrue(brief.contains("Confirmed plan"))
        XCTAssertTrue(brief.contains("Side effects: 会改文件"))
        XCTAssertTrue(brief.contains("Draft reply"))
        XCTAssertTrue(brief.contains("已经补上安装步骤。"))
        XCTAssertTrue(brief.contains("This project"))
        XCTAssertTrue(brief.contains("read-only tools"))
        XCTAssertFalse(brief.contains("Recorded effects"))
        XCTAssertFalse(brief.contains("This turn"))
        XCTAssertFalse(brief.contains("Places to inspect"))
    }

    func testBriefListsInspectPlacesWithoutDiffs() {
        let brief = ReviewAgent.brief(
            userText: "补安装说明",
            workPlan: WorkPlan(kind: .act, intent: "补安装说明", approach: "只改 Install.md。"),
            draft: "已经补上。",
            sandbox: "This project",
            inspectPlaces: ["Install.md", "clipboard"]
        )
        XCTAssertTrue(brief.contains("Places to inspect"))
        XCTAssertTrue(brief.contains("- Install.md"))
        XCTAssertTrue(brief.contains("- clipboard"))
        XCTAssertFalse(brief.contains("+## Install"))
        XCTAssertFalse(brief.contains("Recorded effects"))
    }

    func testInspectToolsAreReadOnly() {
        XCTAssertTrue(ReviewAgent.inspectToolNames.contains("read_text_file"))
        XCTAssertTrue(ReviewAgent.inspectToolNames.contains("get_clipboard"))
        XCTAssertFalse(ReviewAgent.inspectToolNames.contains("write_text_file"))
        XCTAssertFalse(ReviewAgent.inspectToolNames.contains("run_shell_command"))
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
