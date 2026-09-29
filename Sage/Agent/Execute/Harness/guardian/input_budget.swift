//
//  input_budget.swift
//  Sage
//
//  Port of codex-rs/core/src/guardian/input_budget.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Session-aware pending-review check and finalize. ComposedContext
//  evidence selection waits; stored user inputs stand in for the
//  finalized review attachment.
//

import CodexCore
import CodexProtocol
import Foundation

struct PendingReviewContext: Equatable, Sendable {
    var estimatedTokens: Int
    var userInputs: [UserInput]

    init(estimatedTokens: Int = 0, userInputs: [UserInput] = []) {
        self.estimatedTokens = estimatedTokens
        self.userInputs = userInputs
    }

    init(text: String) {
        userInputs = [.text(text: text, textElements: [])]
        estimatedTokens = PromptBudget.estimatedTokenCount(in: text)
    }
}

enum GuardianInputBudget {
    static let inputTokenMargin = 1_024

    static func checkPending(events: [AgentEvent], usableTokens: Int) -> String? {
        guard let last = events.last(where: { $0.kind == .userInput }) else { return nil }
        let tokens = PromptBudget.estimatedTokenCount(of: last)
        let maximum = max(usableTokens - inputTokenMargin, 1)
        if tokens > maximum {
            return "Guardian review input exceeds the context window."
        }
        return nil
    }

    static func checkPending(session: Session, turn: TurnContext) throws {
        guard let pending = session.pendingReviewContext else { return }
        let base = session.getPromptBaseInstructions()
        let minimumPrefix = TruncationPolicy.bytes(base.text.utf8.count).tokenBudget
        let maximum = max(
            effectiveInputTokenLimit(
                model: turn.modelInfoValue(),
                configuredWindow: turn.config.modelContextWindow ?? turn.modelContextWindow
            ) - GuardianRequestBudget.inputTokenMargin,
            1
        )
        if pending.estimatedTokens.saturatingAdd(minimumPrefix) > maximum {
            session.exhaustedReviewBudget = .detected
            throw CodexErr(details: .contextWindowExceeded)
        }
    }

    static func finalize(
        session: Session,
        step: StepContext,
        input: inout [SessionTurnInput]
    ) throws {
        guard let pending = session.pendingReviewContext else { return }
        guard input.count == 1, case .userInput(var content, let clientId, let metadata) = input[0] else {
            throw CodexErr(details: .invalidRequest("Guardian expects one review input"))
        }
        let model = step.turn.modelInfoValue()
        let historyTokens = session.cloneHistory().forPrompt().reduce(0) { partial, item in
            partial.saturatingAdd(estimateItemTokenCount(item))
        }
        let existing = max(historyTokens, Int(clamping: session.getTotalTokenUsage()))
        var framing = responseItemFromUserInput(content)
        if case .message(let id, let role, _, let phase, let metadataPassthrough) = framing {
            framing = .message(
                id: id,
                role: role,
                content: [],
                phase: phase,
                internalChatMessageMetadataPassthrough: metadataPassthrough
            )
        }
        let budget = max(
            effectiveInputTokenLimit(
                model: model,
                configuredWindow: step.turn.config.modelContextWindow ?? step.turn.modelContextWindow
            ) - GuardianRequestBudget.inputTokenMargin,
            1
        )
        let reserved = existing.saturatingAdd(estimateItemTokenCount(framing))
        if pending.estimatedTokens.saturatingAdd(reserved) > budget {
            session.exhaustedReviewBudget = .detected
            throw CodexErr(details: .contextWindowExceeded)
        }
        content = pending.userInputs
        input[0] = .userInput(content: content, clientId: clientId, metadata: metadata)
        session.pendingReviewContext = nil
        session.exhaustedReviewBudget = nil
    }
}

private extension Int {
    func saturatingAdd(_ other: Int) -> Int {
        let (result, overflow) = addingReportingOverflow(other)
        return overflow ? Int.max : result
    }
}
