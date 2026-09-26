//
//  model.swift
//  CodexCore
//
//  Port of codex-rs/core/src/context/world_state/model.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import Foundation

public struct ModelInstructionsState: Equatable, Sendable {
    public var model: String?

    public init(model: String? = nil) {
        self.model = model
    }

    public func snapshot() -> String? { model }

    public func renderDiff(previous: String?) -> (any ContextualUserFragment)? {
        guard let model, let previous, model != previous else { return nil }
        return ModelSwitchInstructions(previousModel: previous, currentModel: model)
    }
}
