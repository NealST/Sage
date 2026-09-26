//
//  model_switch_instructions.swift
//  CodexCore
//
//  Port of codex-rs/core/src/context/model_switch_instructions.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import CodexProtocol
import Foundation

public struct ModelSwitchInstructions: ContextualUserFragment, Equatable, Sendable {
    public var previousModel: String
    public var currentModel: String

    public init(previousModel: String, currentModel: String) {
        self.previousModel = previousModel
        self.currentModel = currentModel
    }

    public var contentKind: ContentItemKind { ContentItemKind("model.switch") }
    public var role: String { "developer" }
    public var openMarker: String { "<model_switch_instructions>" }
    public var closeMarker: String { "</model_switch_instructions>" }
    public var body: String {
        "The session model changed from \(previousModel) to \(currentModel). Continue from the existing transcript without restating prior work."
    }
}
