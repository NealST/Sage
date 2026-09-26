//
//  compact_model_fallback.swift
//  CodexCore
//
//  Port of codex-rs/core/src/compact_model_fallback.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import Foundation

public struct CompactModelFallback: Equatable, Sendable {
    public var model: String?

    public init(model: String? = nil) {
        self.model = model
    }
}
