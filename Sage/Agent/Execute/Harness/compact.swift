//
//  compact.swift
//  CodexCore
//
//  Port of codex-rs/core/src/compact.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Session-aware remote compaction waits for a ModelClient (Phase 6).
//  This file ports injection policy, summary wrapping, and token caps.
//

import CodexProtocol
import CodexUtils
import Foundation

public let compactUserMessageMaxTokens = 20_000

public enum InitialContextInjection: Sendable {
    case beforeLastUserMessage
    case doNotInject
}

public struct CompactionCheckpointMetadata: Equatable, Sendable {
    public var windowNumber: UInt64
    public var summary: String

    public init(windowNumber: UInt64, summary: String) {
        self.windowNumber = windowNumber
        self.summary = summary
    }
}

public func wrapCompactionSummary(_ summary: String) -> ResponseItem {
    CompactionSummary(summary: summary).asResponseItem()
}

public func capCompactUserMessage(_ text: String) -> String {
    truncateTextByTokens(text, tokenBudget: compactUserMessageMaxTokens)
}
