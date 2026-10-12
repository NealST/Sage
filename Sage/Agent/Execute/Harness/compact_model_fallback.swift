//
//  compact_model_fallback.swift
//  SageCore
//
//  Port of codex-rs/core/src/compact_model_fallback.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import SageProtocol
import Foundation

public struct CompactModelFallback: Equatable, Sendable {
    public var previousModel: String
    public var currentModel: String
    public var succeeded: Bool

    public init(previousModel: String, currentModel: String, succeeded: Bool) {
        self.previousModel = previousModel
        self.currentModel = currentModel
        self.succeeded = succeeded
    }
}

public func shouldRetryWithCurrentModel(_ error: SageErr) -> Bool {
    switch error.details {
    case .turnAborted, .interrupted, .sessionBudgetExceeded:
        return false
    default:
        return true
    }
}

public func recordModelFallback(
    previousModel: String,
    currentModel: String,
    fallbackError: SageErr?
) -> CompactModelFallback {
    CompactModelFallback(
        previousModel: previousModel,
        currentModel: currentModel,
        succeeded: fallbackError == nil
    )
}
