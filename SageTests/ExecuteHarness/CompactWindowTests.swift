@testable import Sage
import CodexCore
import CodexExecPolicy
import CodexProtocol
import XCTest

final class ExecuteHarnessCompactWindowTests: XCTestCase {
    func testSelectStrategyPrefersTokenBudgetThenRemoteV2() {
        XCTAssertEqual(
            CompactTask.selectStrategy(tokenBudgetEnabled: true, remoteV2Available: true),
            .tokenBudget
        )
        XCTAssertEqual(
            CompactTask.selectStrategy(tokenBudgetEnabled: false, remoteV2Available: true),
            .remoteV2
        )
        XCTAssertEqual(
            CompactTask.selectStrategy(tokenBudgetEnabled: false, remoteV2Available: false),
            .local
        )
    }

    func testResetWindowAdvancesAndClearsPrefill() {
        var window = AutoCompactWindow.newWithIds(.newInitial())
        window.setEstimatedPrefill(1_200)
        XCTAssertEqual(window.windowNumber, 0)
        XCTAssertNotNil(window.snapshot().prefillInputTokens)

        let (number, ids) = CompactTask.resetWindow(&window)
        XCTAssertEqual(number, 1)
        XCTAssertNotEqual(ids.windowId, ids.previousWindowId)
        XCTAssertNil(window.snapshot().prefillInputTokens)
        XCTAssertFalse(window.tokenBudgetReminderDelivered)
        XCTAssertFalse(window.autoCompactFallbackDelivered)
    }

    func testOccupancyThresholdMatchesTokenBudget() {
        XCTAssertEqual(CompactTask.autoCompactThreshold, CompactTokenBudget.autoCompactThreshold)
        XCTAssertTrue(
            CompactTokenBudget(usableTokens: 100, usedTokens: 90).shouldCompact
        )
        XCTAssertFalse(
            CompactTokenBudget(usableTokens: 100, usedTokens: 89).shouldCompact
        )
    }

    func testRunAutoCompactAdvancesWindowAndClearsPrefill() async throws {
        let sess = Session()
        sess.state.recordItems([
            .message(
                id: nil,
                role: "user",
                content: [.inputText(text: "keep me")],
                phase: nil,
                internalChatMessageMetadataPassthrough: nil
            ),
            .message(
                id: nil,
                role: "assistant",
                content: [.outputText(text: "long tool chatter")],
                phase: nil,
                internalChatMessageMetadataPassthrough: nil
            ),
        ])
        sess.state.setAutoCompactWindowEstimatedPrefill(800)
        sess.runCompactOverride = { _ in "folded work" }
        var client: ModelClientSession?
        try await runAutoCompact(
            sess: sess,
            stepContext: StepContext(),
            clientSession: &client,
            injection: .doNotInject
        )

        XCTAssertEqual(sess.state.autoCompactWindowNumber(), 1)
        XCTAssertNil(sess.autoCompactWindowSnapshot().prefillInputTokens)
        XCTAssertEqual(sess.lastCompactCheckpoint?.windowNumber, 1)
        XCTAssertEqual(sess.lastCompactCheckpoint?.summary, "folded work")
        XCTAssertEqual(sess.lastRemoteCompact?.summary, "folded work")
        XCTAssertEqual(sess.lastRemoteCompact?.succeeded, true)
        let prompt = sess.cloneHistory().forPrompt()
        XCTAssertEqual(prompt.count, 2)
        XCTAssertEqual(contentItemsToText(responseMessageContent(prompt[0])), "keep me")
        XCTAssertEqual(prompt[1], wrapCompactionSummary("folded work"))
        XCTAssertTrue(sess.emittedEvents.contains { event in
            if case .contextCompacted = event { return true }
            return false
        })
    }

    func testTokenBudgetCompactSkipsModelAndResetsWindow() async throws {
        let sess = Session(features: Features([.tokenBudget]))
        sess.state.recordItems([
            .message(
                id: nil,
                role: "user",
                content: [.inputText(text: "keep the ask")],
                phase: nil,
                internalChatMessageMetadataPassthrough: nil
            ),
            .message(
                id: nil,
                role: "assistant",
                content: [.outputText(text: "tool dump")],
                phase: nil,
                internalChatMessageMetadataPassthrough: nil
            ),
        ])
        sess.state.setAutoCompactWindowEstimatedPrefill(400)
        var compactCalls = 0
        sess.runCompactOverride = { _ in
            compactCalls += 1
            return "should not run"
        }
        var client: ModelClientSession?
        try await runAutoCompact(
            sess: sess,
            stepContext: StepContext(),
            clientSession: &client,
            injection: .doNotInject
        )

        XCTAssertEqual(compactCalls, 0)
        XCTAssertEqual(sess.state.autoCompactWindowNumber(), 1)
        XCTAssertNil(sess.autoCompactWindowSnapshot().prefillInputTokens)
        XCTAssertEqual(sess.lastCompactCheckpoint?.windowNumber, 1)
        XCTAssertEqual(sess.lastCompactCheckpoint?.summary, compactNoSummaryAvailable)
        let prompt = sess.cloneHistory().forPrompt()
        XCTAssertEqual(prompt.count, 2)
        XCTAssertEqual(contentItemsToText(responseMessageContent(prompt[0])), "keep the ask")
        XCTAssertEqual(prompt[1], wrapCompactionSummary(compactNoSummaryAvailable))
        XCTAssertTrue(sess.emittedEvents.contains { event in
            if case .itemStarted(let started) = event, case .contextCompaction = started.item {
                return true
            }
            return false
        })
    }

    func testCompactTaskRunFollowsTokenBudgetStrategy() async throws {
        let sess = Session(features: Features([.tokenBudget]))
        sess.state.recordItems([
            .message(
                id: nil,
                role: "user",
                content: [.inputText(text: "ask")],
                phase: nil,
                internalChatMessageMetadataPassthrough: nil
            ),
        ])
        var compactCalls = 0
        sess.runCompactOverride = { _ in
            compactCalls += 1
            return "nope"
        }
        var client: ModelClientSession?
        try await CompactTask.run(
            sess: sess,
            stepContext: StepContext(),
            clientSession: &client,
            injection: .doNotInject
        )
        XCTAssertEqual(compactCalls, 0)
        XCTAssertEqual(sess.state.autoCompactWindowNumber(), 1)
    }

    func testInsertsInitialContextBeforeLastUserAndKeepsSummaryLast() {
        let first = userEnvelope("first")
        let second = userEnvelope("second")
        let summary = ResponseItemEnvelope(wrapCompactionSummary("folded"))
        let env = userEnvelope("<environment_context>")
        let result = insertInitialContextBeforeLastRealUserOrSummary(
            [first, second, summary],
            initialContext: [env]
        )
        XCTAssertEqual(promptTexts(result), [
            "first",
            "<environment_context>",
            "second",
            "folded",
        ])
    }

    func testInsertsInitialContextBeforeSummaryWhenNoRealUserRemains() {
        let summary = ResponseItemEnvelope(wrapCompactionSummary("folded"))
        let env = userEnvelope("cwd")
        let result = insertInitialContextBeforeLastRealUserOrSummary(
            [summary],
            initialContext: [env]
        )
        XCTAssertEqual(promptTexts(result), [
            "cwd",
            "folded",
        ])
    }

    func testBuildWorldStateForStepRendersEnvironmentAndDeveloper() {
        let sess = Session()
        let turn = TurnContext(
            cwd: "/tmp/proj",
            config: Config(developerInstructions: "keep the policy")
        )
        let world = sess.buildWorldStateForStep(StepContext(turn: turn))
        XCTAssertEqual(world.model.model, "gpt-5")
        XCTAssertTrue(world.environment.rendered?.contains("/tmp/proj") == true)
        XCTAssertEqual(world.managedDeveloperInstructions.text, "keep the policy")
        let fragments = world.renderFull().map { $0.renderedText() }
        XCTAssertTrue(fragments.contains { $0.contains("<environment_context>") })
        XCTAssertTrue(fragments.contains { $0.contains("keep the policy") })
    }

    func testFormatAllowPrefixesSortsAndQuotesTokens() {
        XCTAssertNil(formatAllowPrefixes([]))
        let rendered = formatAllowPrefixes([["git", "status"], ["ls"]])
        XCTAssertEqual(
            rendered,
            """
            - ["ls"]
            - ["git", "status"]
            """
        )
    }

    func testBuildWorldStateIncludesExecPolicyPrefixes() throws {
        let sess = Session()
        let policy = Policy.empty()
        try policy.addPrefixRule(["git", "status"], decision: .allow)
        sess.services.execPolicy = policy
        let world = sess.buildWorldStateForStep(
            StepContext(turn: TurnContext(cwd: "/tmp/proj"))
        )
        XCTAssertTrue(
            world.permissions.rendered?.contains(approvedCommandPrefixSavedMessagePrefix) == true
        )
        XCTAssertTrue(world.permissions.rendered?.contains("[\"git\", \"status\"]") == true)
    }

    func testRunAutoCompactReinjectsApprovedPrefixes() async throws {
        let sess = Session()
        let policy = Policy.empty()
        try policy.addPrefixRule(["git", "status"], decision: .allow)
        sess.services.execPolicy = policy
        sess.state.recordItems([
            .message(
                id: nil,
                role: "user",
                content: [.inputText(text: "keep me")],
                phase: nil,
                internalChatMessageMetadataPassthrough: nil
            ),
        ])
        sess.runCompactOverride = { _ in "folded work" }
        var client: ModelClientSession?
        try await runAutoCompact(
            sess: sess,
            stepContext: StepContext(turn: TurnContext(cwd: "/tmp/proj")),
            clientSession: &client,
            injection: .beforeLastUserMessage
        )
        let texts = promptTexts(sess.cloneHistory().items)
        XCTAssertTrue(texts.contains { $0.contains(approvedCommandPrefixSavedMessagePrefix) })
        XCTAssertTrue(texts.contains { $0.contains("[\"git\", \"status\"]") })
        XCTAssertEqual(texts.last, "folded work")
    }

    func testRunAutoCompactReinjectsInitialContextBeforeLastUser() async throws {
        let sess = Session()
        sess.state.recordItems([
            .message(
                id: nil,
                role: "user",
                content: [.inputText(text: "keep me")],
                phase: nil,
                internalChatMessageMetadataPassthrough: nil
            ),
            .message(
                id: nil,
                role: "assistant",
                content: [.outputText(text: "long tool chatter")],
                phase: nil,
                internalChatMessageMetadataPassthrough: nil
            ),
        ])
        sess.runCompactOverride = { _ in "folded work" }
        var client: ModelClientSession?
        try await runAutoCompact(
            sess: sess,
            stepContext: StepContext(
                turn: TurnContext(
                    cwd: "/tmp/proj",
                    config: Config(developerInstructions: "keep the policy")
                )
            ),
            clientSession: &client,
            injection: .beforeLastUserMessage
        )
        let texts = promptTexts(sess.cloneHistory().items)
        XCTAssertTrue(texts.contains { $0.contains("<environment_context>") && $0.contains("/tmp/proj") })
        XCTAssertTrue(texts.contains { $0.contains("keep the policy") })
        XCTAssertEqual(texts.last, "folded work")
        XCTAssertTrue(texts.contains("keep me"))
        let keepIndex = try XCTUnwrap(texts.firstIndex(of: "keep me"))
        XCTAssertTrue(keepIndex > 0)
    }

    func testDoNotInjectLeavesCompactedHistoryWithoutWorldState() async throws {
        let sess = Session()
        sess.state.recordItems([
            .message(
                id: nil,
                role: "user",
                content: [.inputText(text: "keep me")],
                phase: nil,
                internalChatMessageMetadataPassthrough: nil
            ),
        ])
        sess.runCompactOverride = { _ in "folded work" }
        var client: ModelClientSession?
        try await runAutoCompact(
            sess: sess,
            stepContext: StepContext(
                turn: TurnContext(cwd: "/tmp/proj")
            ),
            clientSession: &client,
            injection: .doNotInject
        )
        let texts = promptTexts(sess.cloneHistory().items)
        XCTAssertEqual(texts, ["keep me", "folded work"])
    }
}

private func userEnvelope(_ text: String) -> ResponseItemEnvelope {
    ResponseItemEnvelope(
        .message(
            id: nil,
            role: "user",
            content: [.inputText(text: text)],
            phase: nil,
            internalChatMessageMetadataPassthrough: nil
        )
    )
}

private func promptTexts(_ items: [ResponseItemEnvelope]) -> [String] {
    items.compactMap { contentItemsToText(responseMessageContent($0.item)) }
}

private func responseMessageContent(_ item: ResponseItem) -> [ContentItem] {
    if case .message(_, _, let content, _, _) = item { return content }
    return []
}
