//
//  reasoning_effort.swift
//  Sage
//
//  Port of codex-rs/core/src/session/reasoning_effort.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import CodexProtocol
import Foundation

extension Session {
    func pinnedReasoningEffort(model: String) -> ReasoningEffort? {
        state.reasoningEffortPin.get(model)
    }

    func pinReasoningEffort(model: String, effort: ReasoningEffort) -> ReasoningEffort {
        state.reasoningEffortPin.pin(model: model, effort: effort)
    }
}
