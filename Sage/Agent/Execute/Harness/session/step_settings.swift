//
//  step_settings.swift
//  Sage
//
//  Port of codex-rs/core/src/session/step_settings.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import CodexProtocol
import Foundation

struct ModelInfoOverrides: Equatable, Sendable {
    var model: String?
    var reasoningEffort: ReasoningEffort?

    init(model: String? = nil, reasoningEffort: ReasoningEffort? = nil) {
        self.model = model
        self.reasoningEffort = reasoningEffort
    }
}

struct StepSettingsConstraints: Equatable, Sendable {
    var model: String?
    var reasoningEffort: ReasoningEffort?

    init(model: String? = nil, reasoningEffort: ReasoningEffort? = nil) {
        self.model = model
        self.reasoningEffort = reasoningEffort
    }
}

struct StepSettingsUpdate: Equatable, Sendable {
    var model: String?
    var reasoningEffort: ReasoningEffort?

    init(model: String? = nil, reasoningEffort: ReasoningEffort? = nil) {
        self.model = model
        self.reasoningEffort = reasoningEffort
    }
}

struct StepSettings: Equatable, Sendable {
    var model: String
    var reasoningEffort: ReasoningEffort?
    var serviceTier: String?

    init(
        model: String = "gpt-5",
        reasoningEffort: ReasoningEffort? = nil,
        serviceTier: String? = nil
    ) {
        self.model = model
        self.reasoningEffort = reasoningEffort
        self.serviceTier = serviceTier
    }

    func applying(_ update: StepSettingsUpdate) -> StepSettings {
        StepSettings(
            model: update.model ?? model,
            reasoningEffort: update.reasoningEffort ?? reasoningEffort,
            serviceTier: serviceTier
        )
    }
}

typealias ResolvedStepSettings = StepSettings
