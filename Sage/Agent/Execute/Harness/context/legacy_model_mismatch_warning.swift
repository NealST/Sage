//
//  legacy_model_mismatch_warning.swift
//  CodexCore
//
//  Port of codex-rs/core/src/context/legacy_model_mismatch_warning.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//

import CodexProtocol
import Foundation

public struct LegacyModelMismatchWarning: ContextualUserFragment, Equatable, Sendable {
    public init() {}

    public var contentKind: ContentItemKind { ContentItemKind("legacy.model_mismatch") }
    public var role: String { "user" }
    public var openMarker: String { "<legacy_model_mismatch_warning>" }
    public var closeMarker: String { "</legacy_model_mismatch_warning>" }
    public var body: String {
        "This thread was started with a different model. Continue with the current model and do not assume hidden prior capabilities."
    }
}
