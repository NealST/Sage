//
//  request_budget.swift
//  Sage
//
//  Port of codex-rs/core/src/guardian/request_budget.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Checks the assembled reviewer prompt, including the margin Codex keeps
//  so a continuation cannot overflow the window. Request-token estimate
//  uses history items + instructions until ResponsesApiRequest exists.
//

import CodexCore
import CodexProtocol
import Foundation

enum ExhaustedReviewBudget: Equatable {
    case detected
    case compacting
}

enum GuardianRequestBudget {
    static let inputTokenMargin = 256
    static let defaultMaxInputTokens = 128_000

    static func estimateTokens(prompt: String, instructions: String) -> Int {
        PromptBudget.estimatedTokenCount(in: prompt) + PromptBudget.estimatedTokenCount(in: instructions)
    }

    static func check(prompt: String, instructions: String, usableTokens: Int) -> ExhaustedReviewBudget? {
        let total = estimateTokens(prompt: prompt, instructions: instructions)
        let limit = max(usableTokens - inputTokenMargin, 1)
        if total > limit {
            return .detected
        }
        return nil
    }

    static func estimateRequestTokens(prompt: Prompt) -> Int {
        let input = prompt.input.reduce(0) { partial, item in
            let (result, overflow) = partial.addingReportingOverflow(estimateItemTokenCount(item))
            return overflow ? Int.max : result
        }
        let instructions = TruncationPolicy.bytes(prompt.baseInstructions.text.utf8.count).tokenBudget
        let (total, overflow) = input.addingReportingOverflow(instructions)
        return overflow ? Int.max : total
    }

    static func checkPrompt(
        session: Session,
        prompt: Prompt,
        config: Config,
        model: ModelInfo
    ) throws {
        let limit = max(
            effectiveInputTokenLimit(model: model, configuredWindow: config.modelContextWindow) - inputTokenMargin,
            1
        )
        if estimateRequestTokens(prompt: prompt) > limit {
            session.exhaustedReviewBudget = .detected
            throw CodexErr(details: .contextWindowExceeded)
        }
        session.exhaustedReviewBudget = nil
    }
}

func effectiveInputTokenLimit(model: ModelInfo, configuredWindow: Int64?) -> Int {
    var supported = model.resolvedContextWindow() ?? Int64(GuardianRequestBudget.defaultMaxInputTokens)
    if model.usedFallbackModelMetadata {
        supported = min(supported, Int64(GuardianRequestBudget.defaultMaxInputTokens))
    }
    let window = min(configuredWindow ?? supported, supported)
    let percent = min(max(model.effectiveContextWindowPercent, 0), 100)
    let limit = (window &* percent) / 100
    return Int(max(limit, 0))
}
