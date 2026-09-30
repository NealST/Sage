@testable import Sage
import CodexProtocol
import XCTest

final class ExecuteHarnessTokenBudgetConfigTests: XCTestCase {
    func testFallbackBufferRequiresAPrompt() {
        var config = TokenBudgetConfig(autoCompactFallbackBufferTokens: 20)
        XCTAssertEqual(config.fallbackBufferTokens(), 0)

        config.autoCompactFallbackPrompt = "continue with the current window"
        XCTAssertEqual(config.fallbackBufferTokens(), 20)
    }

    func testValidateRejectsPromptWithoutBuffer() {
        let config = TokenBudgetConfig(autoCompactFallbackPrompt: "keep going")
        switch config.validate() {
        case .success:
            XCTFail("expected a missing-buffer reject")
        case .failure(let error):
            XCTAssertTrue(error.description.contains("auto_compact_fallback_buffer_tokens"))
        }
    }

    func testValidateRejectsEmptyReminderTemplate() {
        let config = TokenBudgetConfig(reminderMessageTemplate: "   ")
        switch config.validate() {
        case .success:
            XCTFail("expected an empty-template reject")
        case .failure(let error):
            XCTAssertTrue(error.description.contains("reminder_message_template"))
        }
    }

    func testResolveKeepsConfiguredWhenDefaultsAreOff() {
        let configured = TokenBudgetConfig(useHistoryNotesExtension: true)
        let resolved = resolveTokenBudgetConfig(
            configured: configured,
            useModelDefaults: false,
            modelDefaults: ModelTokenBudgetConfig(
                reminderThresholdTokens: 40,
                reminderMessageTemplate: "Model reminder",
                guidanceMessage: "guidance",
                autoCompactFallbackPrompt: "fallback",
                autoCompactFallbackBufferTokens: 16
            )
        )
        XCTAssertEqual(resolved, configured)
    }

    func testResolveFillsModelDefaultsAndKeepsNotesFlag() throws {
        let resolved = try XCTUnwrap(
            resolveTokenBudgetConfig(
                configured: TokenBudgetConfig(useHistoryNotesExtension: true),
                useModelDefaults: true,
                modelDefaults: ModelTokenBudgetConfig(
                    reminderThresholdTokens: 40,
                    reminderMessageTemplate: "Model reminder",
                    guidanceMessage: "guidance",
                    autoCompactFallbackPrompt: "fallback",
                    autoCompactFallbackBufferTokens: 16
                )
            )
        )
        XCTAssertTrue(resolved.useHistoryNotesExtension)
        XCTAssertEqual(resolved.reminderThresholdTokens, 40)
        XCTAssertEqual(resolved.reminderMessageTemplate, "Model reminder")
        XCTAssertEqual(resolved.autoCompactFallbackPrompt, "fallback")
        XCTAssertEqual(resolved.fallbackBufferTokens(), 16)
    }

    func testResolveDropsInvalidModelDefaults() {
        let configured = TokenBudgetConfig(reminderMessageTemplate: "keep mine")
        let resolved = resolveTokenBudgetConfig(
            configured: configured,
            useModelDefaults: true,
            modelDefaults: ModelTokenBudgetConfig(
                reminderThresholdTokens: 40,
                reminderMessageTemplate: "",
                guidanceMessage: "guidance",
                autoCompactFallbackPrompt: "fallback",
                autoCompactFallbackBufferTokens: 16
            )
        )
        XCTAssertEqual(resolved, configured)
    }

    func testContextWindowUsesFallbackBuffer() {
        let sess = Session()
        sess.state.setTokenUsageFull(100)
        let turn = TurnContext(
            modelContextWindow: 200,
            effectiveContextWindowPercent: 100,
            autoCompactTokenLimitValue: 100,
            config: Config(
                tokenBudget: TokenBudgetConfig(
                    autoCompactFallbackPrompt: "keep going",
                    autoCompactFallbackBufferTokens: 20
                )
            )
        )
        let status = contextWindowTokenStatus(sess: sess, turnContext: turn)
        XCTAssertEqual(status.autoCompactScopeLimit, 100)
        XCTAssertFalse(status.tokenLimitReached)
        XCTAssertFalse(status.fullContextWindowLimitReached)
    }

    func testContextWindowWithoutPromptIgnoresBuffer() {
        let sess = Session()
        sess.state.setTokenUsageFull(100)
        let turn = TurnContext(
            modelContextWindow: 200,
            effectiveContextWindowPercent: 100,
            autoCompactTokenLimitValue: 100,
            config: Config(
                tokenBudget: TokenBudgetConfig(autoCompactFallbackBufferTokens: 20)
            )
        )
        let status = contextWindowTokenStatus(sess: sess, turnContext: turn)
        XCTAssertTrue(status.tokenLimitReached)
    }

    func testContextWindowReachesBufferedLimit() {
        let sess = Session()
        sess.state.setTokenUsageFull(120)
        let turn = TurnContext(
            modelContextWindow: 200,
            effectiveContextWindowPercent: 100,
            autoCompactTokenLimitValue: 100,
            config: Config(
                tokenBudget: TokenBudgetConfig(
                    autoCompactFallbackPrompt: "keep going",
                    autoCompactFallbackBufferTokens: 20
                )
            )
        )
        XCTAssertTrue(contextWindowTokenStatus(sess: sess, turnContext: turn).tokenLimitReached)
    }
}
