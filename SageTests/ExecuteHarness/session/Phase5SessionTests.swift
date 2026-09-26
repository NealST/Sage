import CodexCore
import CodexProtocol
import XCTest
@testable import Sage

final class Phase5SessionTests: XCTestCase {
    func testAutoCompactWindowTracksPrefillAndBoundaries() {
        var window = AutoCompactWindow.newWithIds(.newInitial())
        XCTAssertEqual(window.windowNumber, 0)
        let first = window.ids.windowId
        XCTAssertEqual(window.ids.firstWindowId, first)
        XCTAssertNil(window.ids.previousWindowId)

        XCTAssertTrue(window.claimTokenBudgetReminder())
        XCTAssertFalse(window.claimTokenBudgetReminder())
        XCTAssertTrue(window.claimAutoCompactFallback())
        XCTAssertFalse(window.claimAutoCompactFallback())

        window.requestNewContextWindow()
        XCTAssertTrue(window.takeNewContextWindowRequest())
        XCTAssertFalse(window.takeNewContextWindowRequest())

        window.setEstimatedPrefill(150)
        XCTAssertEqual(window.snapshot().prefillInputTokens, 150)

        window.ensureServerObservedPrefillFromUsage(CodexProtocol.TokenUsage(inputTokens: 120, totalTokens: 170))
        XCTAssertEqual(window.snapshot().prefillInputTokens, 120)
        window.setEstimatedPrefill(90)
        XCTAssertEqual(window.snapshot().prefillInputTokens, 120)

        let (number, ids) = window.advance()
        XCTAssertEqual(number, 1)
        XCTAssertEqual(ids.previousWindowId, first)
        XCTAssertNotEqual(ids.windowId, first)
        XCTAssertTrue(window.claimTokenBudgetReminder())
    }

    func testTokenUsageAddAssignAndRemainingPercent() {
        var usage = CodexProtocol.TokenUsage(inputTokens: 10, cachedInputTokens: 4, outputTokens: 3, totalTokens: 13)
        usage.addAssign(CodexProtocol.TokenUsage(inputTokens: 5, cachedInputTokens: 1, outputTokens: 2, totalTokens: 7))
        XCTAssertEqual(usage.inputTokens, 15)
        XCTAssertEqual(usage.cachedInput(), 5)
        XCTAssertEqual(usage.nonCachedInput(), 10)
        XCTAssertEqual(usage.blendedTotal(), 15)
        XCTAssertGreaterThan(usage.percentOfContextWindowRemaining(32_000), 0)
    }

    func testContextManagerRecordsAndReplaces() {
        let manager = ContextManager()
        manager.recordItems([
            .message(id: nil, role: "user", content: [.inputText(text: "hello")], phase: nil, internalChatMessageMetadataPassthrough: nil)
        ])
        XCTAssertEqual(manager.items.count, 1)
        XCTAssertTrue(isUserTurnBoundary(manager.items[0].item))
        manager.replaceAnnotated([])
        XCTAssertTrue(manager.items.isEmpty)
        XCTAssertEqual(manager.resetVersion, 1)
    }

    func testSessionStateTokenUsageAndWindowAdvance() {
        let state = SessionState(sessionConfiguration: SessionConfiguration())
        let record = state.recordTokenUsage(
            threadId: ThreadId(),
            turnId: "t1",
            sessionId: SessionId(),
            rootTurnId: "t1",
            responseId: "r1",
            usage: CodexProtocol.TokenUsage(inputTokens: 8, outputTokens: 2, totalTokens: 10)
        )
        XCTAssertEqual(record.turnTokenUsage.totalTokens, 10)
        let (number, _) = state.startNewContextWindow()
        XCTAssertEqual(number, 1)
        XCTAssertNil(state.autoCompactWindowSnapshot().prefillInputTokens)
    }

    func testUserInstructionsAndTimeReminderFragments() {
        let instructions = UserInstructions(directory: "/tmp", text: "Be concise")
        XCTAssertTrue(instructions.body.contains("for /tmp"))
        XCTAssertTrue(instructions.renderedText().contains("</INSTRUCTIONS>"))

        let reminder = CurrentTimeReminder(currentTime: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(reminder.formattedTime(), "1970-01-01 00:00:00 UTC")
        XCTAssertTrue(reminder.body.contains("1970-01-01"))
    }

    func testEnsureCallOutputsPresentInsertsAbortedOutput() {
        var items = [
            ResponseItemEnvelope(.functionCall(
                id: ResponseItemId(new: "fc"),
                name: "shell",
                namespace: nil,
                arguments: "{}",
                encryptedFunctionArgs: nil,
                callId: "c1",
                internalChatMessageMetadataPassthrough: nil
            ))
        ]
        ensureCallOutputsPresent(&items)
        XCTAssertEqual(items.count, 2)
        if case .functionCallOutput(_, let callId, _, _, _, _) = items[1].item {
            XCTAssertEqual(callId, "c1")
        } else {
            XCTFail("expected function call output")
        }
    }

    func testConfigOverridesAndInterruptedMarker() {
        var config = Config(model: "gpt-5")
        config = config.applying(ConfigOverrides(model: "gpt-5.1"))
        XCTAssertEqual(config.model, "gpt-5.1")
        XCTAssertEqual(
            InterruptedTurnHistoryMarker.fromConfig(config, multiAgentVersion: .v2),
            .developer
        )
        XCTAssertNotNil(interruptedTurnHistoryMarker(.contextualUser))
    }

    func testCompactTokenBudgetOccupancy() {
        let budget = CompactTokenBudget(usableTokens: 100, usedTokens: 91)
        XCTAssertEqual(budget.occupancy, 0.91, accuracy: 0.001)
        XCTAssertTrue(budget.shouldCompact)
    }
}
