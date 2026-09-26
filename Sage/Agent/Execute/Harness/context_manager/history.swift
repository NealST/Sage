//
//  history.swift
//  CodexCore
//
//  Port of codex-rs/core/src/context_manager/history.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Guardian review transcripts, retained-context SHA, and image/audio
//  estimators wait for those crates. Item recording, replacement, and
//  token-info accounting are ported.
//

import CodexProtocol
import CodexUtils
import Foundation

public struct ResponseItemEnvelope: Equatable, Sendable {
    public var item: ResponseItem
    public var metadata: String?

    public init(_ item: ResponseItem, metadata: String? = nil) {
        self.item = item
        self.metadata = metadata
    }
}

public enum HistoryReplacement: Equatable, Sendable {
    case compaction(reviewerCompactionHash: String?)
    case reset
}

public final class ContextManager: @unchecked Sendable {
    public var items: [ResponseItemEnvelope] = []
    public var guardianReviewMode: GuardianContextMode = .threadOwned
    public var retainInheritedUserMessages = false
    public var historyVersion: UInt64 = 0
    public var resetVersion: UInt64 = 0
    public var userMessageRevision: UInt64 = 0
    public var worldStateBaseline: WorldStateSnapshot?
    var tokenInfoValue: TokenUsageInfo?
    var referenceContextItem: TurnContextItem?

    public init() {
        tokenInfoValue = TokenUsageInfo.newOrAppend(info: nil, last: nil, modelContextWindow: nil)
    }

    public func recordItems(_ items: [ResponseItem]) {
        self.items.append(contentsOf: items.map { ResponseItemEnvelope($0) })
        if items.contains(where: isUserTurnBoundary) {
            userMessageRevision += 1
        }
    }

    public func replaceAnnotated(_ items: [ResponseItemEnvelope]) {
        self.items = items
        historyVersion += 1
        resetVersion += 1
        worldStateBaseline = nil
    }

    public func replaceCompacted(
        _ items: [ResponseItemEnvelope],
        reviewerCompactionHash: String?
    ) -> Bool {
        self.items = items
        historyVersion += 1
        worldStateBaseline = nil
        return reviewerCompactionHash == nil
    }

    public func setTokenInfo(_ info: TokenUsageInfo?) {
        tokenInfoValue = info
    }

    public func tokenInfo() -> TokenUsageInfo? {
        tokenInfoValue
    }

    public func updateTokenInfo(_ usage: TokenUsage, modelContextWindow: Int64?) {
        tokenInfoValue = TokenUsageInfo.newOrAppend(
            info: tokenInfoValue,
            last: usage,
            modelContextWindow: modelContextWindow
        )
    }

    public func setTokenUsageFull(_ contextWindow: Int64) {
        tokenInfoValue = .fullContextWindow(contextWindow)
    }

    public func getTotalTokenUsage(serverReasoningIncluded: Bool) -> Int64 {
        _ = serverReasoningIncluded
        return tokenInfoValue?.totalTokenUsage.totalTokens ?? 0
    }

    public func setReferenceContextItem(_ item: TurnContextItem?) {
        referenceContextItem = item
    }

    public func referenceContextItemValue() -> TurnContextItem? {
        referenceContextItem
    }

    public func cloneHistory() -> ContextManager {
        let copy = ContextManager()
        copy.items = items
        copy.guardianReviewMode = guardianReviewMode
        copy.retainInheritedUserMessages = retainInheritedUserMessages
        copy.historyVersion = historyVersion
        copy.resetVersion = resetVersion
        copy.userMessageRevision = userMessageRevision
        copy.tokenInfoValue = tokenInfoValue
        copy.referenceContextItem = referenceContextItem
        copy.worldStateBaseline = worldStateBaseline
        return copy
    }
}

public func isUserTurnBoundary(_ item: ResponseItem) -> Bool {
    item.isUserMessage() && !isGuardianContextMessage(item)
}

public func estimateItemTokenCount(_ item: ResponseItem) -> Int {
    approxTokenCount(estimateItemText(item))
}

public func estimateImageReferenceBytes(_ item: ResponseItem) -> Int {
    0
}

func estimateItemText(_ item: ResponseItem) -> String {
    switch item {
    case .message(_, _, let content, _, _):
        return content.compactMap { part -> String? in
            if case .inputText(let text) = part { return text }
            if case .outputText(let text) = part { return text }
            return nil
        }.joined(separator: "\n")
    case .functionCall(_, let name, _, let arguments, _, let callId, _):
        return "\(name) \(callId) \(arguments)"
    case .functionCallOutput(_, let callId, _, _, let output, _):
        return "\(callId ?? "") \(String(describing: output))"
    default:
        return String(describing: item)
    }
}
