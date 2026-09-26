//
//  compact_remote_history.swift
//  CodexCore
//
//  Port of codex-rs/core/src/compact_remote_history.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import CodexProtocol
import Foundation

public struct CompactRemoteHistory: Equatable, Sendable {
    public var items: [ResponseItem]

    public init(items: [ResponseItem] = []) {
        self.items = items
    }
}
