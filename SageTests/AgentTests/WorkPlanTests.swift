@testable import Sage
import XCTest

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
        XCTAssertEqual(plan?.approach.contains("## 理解"), true)
        XCTAssertEqual(plan?.approach.contains("只改 README"), true)
        XCTAssertEqual(plan?.sideEffects, "会改 README.md")
        XCTAssertEqual(plan?.requiresConfirmation, true)
        XCTAssertEqual(plan?.promptAppendix.contains("Confirmed work plan"), true)
        XCTAssertEqual(plan?.promptAppendix.contains("Sensitive reads and local file mutations"), true)
    }

    func testAnswerReplySkipsExecute() {
        let plan = PlanAgent.parse("""
        {
          "kind": "answer",
          "intent": "回一句闲话",
          "approach": "",
          "reply": "哈哈，今天也挺好的。",
          "side_effects": null
        }
        """)
        XCTAssertEqual(plan?.kind, .answer)
        XCTAssertEqual(plan?.reply, "哈哈，今天也挺好的。")
        XCTAssertEqual(plan?.directReply, "哈哈，今天也挺好的。")
        XCTAssertEqual(plan?.skipsReview, true)
        XCTAssertNotEqual(plan?.requiresConfirmation, true)
    }

    func testAnswerDirectReplyFallsBackToApproach() {
        let plan = PlanAgent.parse("""
        {"kind":"answer","intent":"解释这个报错","approach":"根据上下文说明。","side_effects":null}
        """)
        XCTAssertEqual(plan?.directReply, "根据上下文说明。")
        XCTAssertNil(plan?.reply)
    }

    func testActHasNoDirectReply() {
        let plan = PlanAgent.parse("""
        {"kind":"act","intent":"改 README","approach":"只补一节。","side_effects":"会改 README"}
        """)
        XCTAssertNil(plan?.directReply)
        XCTAssertNil(plan?.reply)
        XCTAssertEqual(plan?.requiresConfirmation, true)
    }

    func testAcceptsLegacyApproachArray() {
        let plan = PlanAgent.parse("""
        {"kind":"answer","intent":"解释这个报错","approach":["根据上下文说明原因"],"side_effects":null}
        """)
        XCTAssertEqual(plan?.kind, .answer)
        XCTAssertEqual(plan?.approach.contains("根据上下文说明原因"), true)
        XCTAssertNotEqual(plan?.requiresConfirmation, true)
        XCTAssertNil(plan?.sideEffects)
    }

    func testStripsMarkdownFenceAroundJSON() {
        let plan = PlanAgent.parse("""
        ```json
        {"kind":"observe","intent":"看看项目结构","approach":"先看根目录再决定读哪些说明。","side_effects":null}
        ```
        """)
        XCTAssertEqual(plan?.kind, .observe)
        XCTAssertEqual(plan?.skipsReview, true)
        XCTAssertEqual(plan?.approach.contains("根目录"), true)
        XCTAssertEqual(plan?.promptAppendix.contains("observe plan"), true)
        XCTAssertEqual(plan?.promptAppendix.contains("Mutating tools are rejected"), true)
    }

    func testUnreadableEnvelopeDoesNotInventAct() {
        XCTAssertThrowsError(
            try PlanAgent.resolveProposal(.envelope(raw: "{", visible: ""), raw: "{")
        ) { error in
            XCTAssertTrue(error is PlanProposalError)
        }
        XCTAssertNil(PlanAgent.parse("{"))
    }

    func testPreambleJSONIsAPlan() throws {
        let raw = """
        好的
        {"kind":"act","intent":"改 README","approach":"只补一节。","side_effects":"会改 README"}
        """
        let fromEnvelope = try PlanAgent.resolveProposal(
            .envelope(raw: raw, visible: "好的"),
            raw: raw
        )
        XCTAssertEqual(fromEnvelope.plan.kind, .act)
        XCTAssertEqual(fromEnvelope.plan.intent, "改 README")
        XCTAssertEqual(fromEnvelope.leadIn, "好的")

        let fromAnswer = try PlanAgent.resolveProposal(.answer(raw), raw: raw)
        XCTAssertEqual(fromAnswer.plan.kind, .act)
    }

    func testPlainAnswerStillAnswers() throws {
        let plan = try PlanAgent.resolveProposal(
            .answer("哈哈，今天也挺好的。"),
            raw: "哈哈，今天也挺好的。"
        )
        XCTAssertEqual(plan.plan.kind, .answer)
        XCTAssertEqual(plan.plan.directReply, "哈哈，今天也挺好的。")
        XCTAssertEqual(plan.leadIn, "")
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
        XCTAssertEqual(plan?.skillNames.isEmpty, true)
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

        let roundLimit = AgentTurnChrome.resolve(
            phase: .awaitingConfirmation,
            hasWorkPlan: true,
            hasToolBatch: false,
            pendingPrompt: .toolRoundLimit(currentLimit: 8, nextLimit: 16)
        )
        XCTAssertEqual(roundLimit, .toolRoundLimit)

        let approvalBeatsBatch = AgentTurnChrome.resolve(
            phase: .awaitingConfirmation,
            hasWorkPlan: true,
            hasToolBatch: true,
            pendingPrompt: .toolApproval(
                toolCallID: "1",
                toolName: "run_shell_command",
                argumentsJSON: "{}",
                title: "Run: ls"
            )
        )
        XCTAssertEqual(approvalBeatsBatch, .toolApproval)

        let failedHidesBoth = AgentTurnChrome.resolve(
            phase: .failed(message: "Stopped"),
            hasWorkPlan: true,
            hasToolBatch: true
        )
        XCTAssertNil(failedHidesBoth)

        let reviewFailed = AgentTurnChrome.resolve(
            phase: .awaitingConfirmation,
            hasWorkPlan: true,
            hasToolBatch: true,
            pendingPrompt: .reviewFailed(draft: "done", message: "Reviewer timed out")
        )
        XCTAssertEqual(reviewFailed, .reviewFailed)

        let reviewMustFix = AgentTurnChrome.resolve(
            phase: .thinking,
            hasWorkPlan: true,
            hasToolBatch: false,
            pendingPrompt: .reviewMustFix(draft: "done", message: "还缺安装步骤")
        )
        XCTAssertEqual(reviewMustFix, .reviewMustFix)

        let mustFixYieldsToBatch = AgentTurnChrome.resolve(
            phase: .executing,
            hasWorkPlan: true,
            hasToolBatch: true,
            pendingPrompt: .reviewMustFix(draft: "done", message: "还缺安装步骤")
        )
        XCTAssertEqual(mustFixYieldsToBatch, .toolBatch)

        let reviewOptional = AgentTurnChrome.resolve(
            phase: .awaitingConfirmation,
            hasWorkPlan: true,
            hasToolBatch: false,
            pendingPrompt: .reviewOptional(draft: "done", message: "目录名可以更短")
        )
        XCTAssertEqual(reviewOptional, .reviewOptional)
    }

    func testParsesPersistAdvice() {
        XCTAssertEqual(PlanAgent.parsePersist(#"{"persist":true,"reason":"可复用"}"#)?.persist, true)
        XCTAssertEqual(PlanAgent.parsePersist(#"{"persist":false}"#)?.persist, false)
        XCTAssertEqual(PlanAgent.parsePersist(#"{"persist":"true"}"#)?.persist, true)
        XCTAssertNil(PlanAgent.parsePersist(#"{"decision":"accept"}"#))
    }
}
