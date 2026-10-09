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
    var turn: TurnContext
    var toolRouter: ToolRouter?
    var environments: [TurnEnvironment]
    /// Binding captured for this step. A later publish does not replace it.
    var mcp: PublishedMcpBinding?

    init(
        stepId: String = UUID().uuidString,
        settings: StepSettings = StepSettings(),
        turn: TurnContext = TurnContext(),
        toolRouter: ToolRouter? = nil,
        environments: [TurnEnvironment] = [],
        mcp: PublishedMcpBinding? = nil
    ) {
        self.stepId = stepId
        self.settings = settings
        self.turn = turn
        self.toolRouter = toolRouter
        self.environments = environments
        self.mcp = mcp
    }
}
