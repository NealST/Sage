//
//  turn_metadata.swift
//  CodexCore
//
//  Port of codex-rs/core/src/turn_metadata.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import Foundation

public struct ExecutionMetadata: Equatable, Sendable {
    public var turnId: String
    public var model: String
    public var startedAt: Date

    public init(turnId: String, model: String, startedAt: Date = Date()) {
        self.turnId = turnId
        self.model = model
        self.startedAt = startedAt
    }
}
