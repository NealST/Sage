//
//  step_context.swift
//  Sage
//
//  Port of codex-rs/core/src/session/step_context.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import Foundation

final class StepContext: @unchecked Sendable {
    var stepId: String
    var settings: StepSettings

    init(stepId: String = UUID().uuidString, settings: StepSettings = StepSettings()) {
        self.stepId = stepId
        self.settings = settings
    }
}
