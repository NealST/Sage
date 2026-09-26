//
//  compact_remote_v2.swift
//  CodexCore
//
//  Port of codex-rs/core/src/compact_remote_v2.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Remote V2 compaction talks to ModelClient in Phase 6. This keeps the
//  attempt/result types used by session wiring.
//

import Foundation

public struct CompactRemoteV2Request: Equatable, Sendable {
    public var model: String
    public var trigger: String

    public init(model: String, trigger: String = "auto") {
        self.model = model
        self.trigger = trigger
    }
}

public struct CompactRemoteV2Result: Equatable, Sendable {
    public var summary: String
    public var succeeded: Bool

    public init(summary: String, succeeded: Bool) {
        self.summary = summary
        self.succeeded = succeeded
    }
}
