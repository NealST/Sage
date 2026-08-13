import XCTest
@testable import Sage

final class ContextBudgetTests: XCTestCase {
    func testCapSkillContentLeavesShortPayloadAlone() {
        let content = "<skill_content name=\"x\">hello</skill_content>"
        XCTAssertEqual(ContextBudget.capSkillContent(content, skillName: "x"), content)
    }

    func testCapSkillContentTruncatesOversizedPayload() {
        let huge = String(repeating: "a", count: ContextBudget.maxSkillContentCharacters + 50)
        let capped = ContextBudget.capSkillContent(huge, skillName: "big")
        XCTAssertTrue(capped.utf8.count < huge.utf8.count)
        XCTAssertTrue(capped.contains("load_skill_resource"))
        XCTAssertTrue(capped.contains("big"))
    }

    func testSelectKeepsProtectedEvents() {
        let protected = AgentEvent(
            kind: .userInput,
            content: "skill body",
            protected: true
        )
        let user = AgentEvent(kind: .userInput, content: "hi")
        let selected = ContextBudget.select(from: [protected, user])
        XCTAssertTrue(selected.contains(where: \.protected))
        XCTAssertTrue(selected.contains(where: { !$0.protected && $0.content == "hi" }))
    }
}
