import XCTest
@testable import Sage

final class WorkPlanTests: XCTestCase {
    func testParsesMarkdownApproach() {
        let raw = """
        {
          "kind": "act",
          "intent": "给 README 补一节安装说明",
          "approach": "## 理解\\n用户要的是安装步骤，不是重写全文。\\n\\n## 约束\\n只改 README，不动代码。\\n\\n## 路径\\n先对照现有结构，再补一节。",
          "side_effects": "会改 README.md"
        }
        """
        let plan = PlanAgent.parse(raw)
        XCTAssertEqual(plan?.kind, .act)
        XCTAssertEqual(plan?.intent, "给 README 补一节安装说明")
        XCTAssertTrue(plan?.approach.contains("## 理解") == true)
        XCTAssertTrue(plan?.approach.contains("只改 README") == true)
        XCTAssertEqual(plan?.sideEffects, "会改 README.md")
        XCTAssertTrue(plan?.requiresConfirmation == true)
        XCTAssertTrue(plan?.promptAppendix.contains("Confirmed work plan") == true)
    }

    func testAcceptsLegacyApproachArray() {
        let plan = PlanAgent.parse("""
        {"kind":"answer","intent":"解释这个报错","approach":["根据上下文说明原因"],"side_effects":null}
        """)
        XCTAssertEqual(plan?.kind, .answer)
        XCTAssertTrue(plan?.approach.contains("根据上下文说明原因") == true)
        XCTAssertFalse(plan?.requiresConfirmation == true)
        XCTAssertNil(plan?.sideEffects)
    }

    func testStripsMarkdownFenceAroundJSON() {
        let plan = PlanAgent.parse("""
        ```json
        {"kind":"observe","intent":"看看项目结构","approach":"先看根目录再决定读哪些说明。","side_effects":null}
        ```
        """)
        XCTAssertEqual(plan?.kind, .observe)
        XCTAssertTrue(plan?.approach.contains("根目录") == true)
    }

    func testFallbackIsActMarkdown() {
        let plan = PlanAgent.fallback(for: "改一下配置")
        XCTAssertEqual(plan.kind, .act)
        XCTAssertTrue(plan.requiresConfirmation)
        XCTAssertTrue(plan.approach.contains("##"))
        XCTAssertEqual(plan.threadAdvice, .continueThread)
        XCTAssertTrue(plan.skillNames.isEmpty)
    }

    func testParsesThreadOfferAndSkills() {
        let plan = PlanAgent.parse("""
        {
          "kind": "observe",
          "intent": "看一下登录流程",
          "approach": "先读现有 auth 代码。",
          "side_effects": null,
          "thread": "offer_fresh",
          "thread_label": "改 README",
          "skills": ["swift-review", "  ", "git-hygiene"]
        }
        """)
        XCTAssertEqual(plan?.threadAdvice, .offerFresh)
        XCTAssertEqual(plan?.threadLabel, "改 README")
        XCTAssertEqual(plan?.skillNames, ["swift-review", "git-hygiene"])
    }

    func testMissingThreadDefaultsToContinue() {
        let plan = PlanAgent.parse("""
        {"kind":"answer","intent":"解释这个报错","approach":"根据上下文说明。","side_effects":null}
        """)
        XCTAssertEqual(plan?.threadAdvice, .continueThread)
        XCTAssertTrue(plan?.skillNames.isEmpty == true)
    }

    func testTurnChromePrefersToolBatchOnceExecuteStarts() {
        let workPlanOnly = AgentTurnChrome.resolve(
            phase: .awaitingConfirmation,
            hasWorkPlan: true,
            hasToolBatch: false
        )
        XCTAssertEqual(workPlanOnly, .workPlan)

        let executingBatch = AgentTurnChrome.resolve(
            phase: .executing,
            hasWorkPlan: true,
            hasToolBatch: true
        )
        XCTAssertEqual(executingBatch, .toolBatch)

        let thinkingHidesStrategy = AgentTurnChrome.resolve(
            phase: .thinking,
            hasWorkPlan: true,
            hasToolBatch: false
        )
        XCTAssertNil(thinkingHidesStrategy)

        let failedHidesBoth = AgentTurnChrome.resolve(
            phase: .failed(message: "Stopped"),
            hasWorkPlan: true,
            hasToolBatch: true
        )
        XCTAssertNil(failedHidesBoth)
    }

    func testParsesPersistAdvice() {
        XCTAssertEqual(PlanAgent.parsePersist(#"{"persist":true,"reason":"可复用"}"#)?.persist, true)
        XCTAssertEqual(PlanAgent.parsePersist(#"{"persist":false}"#)?.persist, false)
        XCTAssertEqual(PlanAgent.parsePersist(#"{"persist":"true"}"#)?.persist, true)
        XCTAssertNil(PlanAgent.parsePersist(#"{"decision":"accept"}"#))
    }
}
