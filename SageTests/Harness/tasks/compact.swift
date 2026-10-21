@testable import Sage
import XCTest

final class ExecuteHarnessCompactTests: XCTestCase {
    func testOccupancyPrefersAPIPromptTokens() {
        XCTAssertEqual(
            CompactTask.occupancy(
                assembledTokens: 1_000,
                usableTokens: 10_000,
                reportedInputTokens: 8_000
            ),
            0.8,
            accuracy: 0.0001
        )
    }

    func testOccupancyFallsBackToCJKAwareEstimate() {
        let estimated = PromptBudget.estimatedTokenCount(in: "你好世界")
        XCTAssertEqual(estimated, 4)
        XCTAssertEqual(
            CompactTask.occupancy(
                assembledTokens: estimated,
                usableTokens: 20,
                reportedInputTokens: nil
            ),
            0.2,
            accuracy: 0.0001
        )
    }

    func testLiveOccupancyAddsEventsAfterTheLastModelCall() {
        let extra = AgentEvent(
            kind: .toolResult,
            content: String(repeating: "x", count: 40)
        )
        let extraTokens = PromptBudget.estimatedTokenCount(of: extra)
        let occupancy = CompactTask.liveOccupancy(
            lastAPIInputTokens: 100,
            eventsAfterLastModel: [extra],
            usableTokens: 200
        )
        XCTAssertEqual(
            occupancy,
            min(Double(100 + extraTokens) / 200.0, 1),
            accuracy: 0.0001
        )
    }

    func testFoldSliceKeepsToolResultsBeforeOldProse() {
        let prose = AgentEvent(
            kind: .assistantResponse,
            content: String(repeating: "chat ", count: 80)
        )
        let tool = AgentEvent(
            kind: .toolResult,
            content: "cargo test ok"
        )
        let budget = PromptBudget(
            windowTokens: 40,
            reservedOutputTokens: 8,
            reservedToolTokens: 0
        )
        let selected = CompactTask.selectFoldSlice([prose, tool], budget: budget)
        XCTAssertTrue(selected.contains { $0.id == tool.id })
        XCTAssertFalse(selected.contains { $0.id == prose.id })
    }

    func testFoldSliceSkipsProtectedSkillPayloads() {
        let skill = AgentEvent(
            kind: .toolResult,
            content: "do not fold this skill",
            protected: true
        )
        let tool = AgentEvent(kind: .toolResult, content: "npm test")
        let selected = CompactTask.selectFoldSlice(
            [skill, tool],
            budget: .default
        )
        XCTAssertFalse(selected.contains { $0.protected })
        XCTAssertTrue(selected.contains { $0.id == tool.id })
    }

    func testFailedOutcomeIsVisibleAndKeepsTheContract() {
        let notice = CompactTask.Outcome.failed("network timeout").notice
        XCTAssertNotNil(notice)
        XCTAssertTrue(notice?.contains("work plan") == true)
        XCTAssertTrue(notice?.contains("network timeout") == true)
        XCTAssertNil(CompactTask.Outcome.folded.notice)
        XCTAssertNil(CompactTask.Outcome.skipped.notice)
    }

    func testContractCheckRequiresWorkPlanAndCapabilityReminder() {
        let layout = PromptLayout(
            baseInstructions: "You are Sage.",
            capabilityReminder: "Work plan kind: act",
            workPlanAppendix: "## Confirmed work plan\nIntent: fix tests"
        )
        XCTAssertTrue(
            CompactTask.contractIsPreserved(
                system: """
                You are Sage.
                Work plan kind: act
                ## Confirmed work plan
                Intent: fix tests
                """,
                layout: layout
            )
        )
        XCTAssertFalse(
            CompactTask.contractIsPreserved(
                system: "You are Sage.\nWork plan kind: act",
                layout: layout
            )
        )
    }

    @MainActor
    func testTokenUsageRemembersTheLastAPIPrompt() {
        let state = AgentSessionState()
        state.addTokenUsage(TokenUsage(input: 1200, output: 80))
        state.addTokenUsage(TokenUsage(input: 1500, output: 40))
        XCTAssertEqual(state.tokenUsage.input, 2700)
        XCTAssertEqual(state.tokenUsage.lastInput, 1500)
        XCTAssertEqual(state.tokenUsage.lastOutput, 40)
    }
}
