//
//  compact_remote_v2_attempt.swift
//  CodexCore
//
//  Port of codex-rs/core/src/compact_remote_v2_attempt.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import Foundation

public struct CompactRemoteV2Attempt: Equatable, Sendable {
    public var attempt: Int
    public var request: CompactRemoteV2Request

    public init(attempt: Int, request: CompactRemoteV2Request) {
        self.attempt = attempt
        self.request = request
    }
}
