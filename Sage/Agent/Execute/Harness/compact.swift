//
//  compact.swift
//  CodexCore
//
//  Port of codex-rs/core/src/compact.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Local compacted-history rebuild and initial-context insertion are
//  live. Remote V2 / ModelClient summarization waits on Session compact
//  streaming.
//

import CodexProtocol
import CodexUtils
import Foundation

public let compactUserMessageMaxTokens = 20_000
public let compactNoSummaryAvailable = "(no summary available)"
/// `codex-rs/prompts/templates/compact/summary_prefix.md`
public let compactSummaryPrefix =
    "Another language model started to solve this problem and produced a summary of its thinking process."

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

public struct CompactedUserMessage: Equatable, Sendable {
    public var id: ResponseItemId?
    public var message: String
    public var internalChatMessageMetadataPassthrough: InternalChatMessageMetadataPassthrough?
    public var harnessMetadata: String?

    public init(
        id: ResponseItemId? = nil,
        message: String,
        internalChatMessageMetadataPassthrough: InternalChatMessageMetadataPassthrough? = nil,
        harnessMetadata: String? = nil
    ) {
        self.id = id
        self.message = message
        self.internalChatMessageMetadataPassthrough = internalChatMessageMetadataPassthrough
        self.harnessMetadata = harnessMetadata
    }
}

public func wrapCompactionSummary(_ summary: String) -> ResponseItem {
    CompactionSummary(summary: summary).asResponseItem()
}

public func capCompactUserMessage(_ text: String) -> String {
    truncateTextByTokens(text, tokenBudget: compactUserMessageMaxTokens)
}

public func contentItemsToText(_ content: [ContentItem]) -> String? {
    let pieces = content.compactMap { item -> String? in
        switch item {
        case .inputText(let text), .outputText(let text):
            return text.isEmpty ? nil : text
        default:
            return nil
        }
    }
    return pieces.isEmpty ? nil : pieces.joined(separator: "\n")
}

public func isSummaryMessage(_ message: String) -> Bool {
    message.hasPrefix(compactSummaryPrefix + "\n")
}

public func collectUserMessages(_ items: [ResponseItem]) -> [CompactedUserMessage] {
    items.compactMap { compactedUserMessage($0, harnessMetadata: nil) }
}

public func collectAnnotatedUserMessages(_ items: [ResponseItemEnvelope]) -> [CompactedUserMessage] {
    items.compactMap { compactedUserMessage($0.item, harnessMetadata: $0.metadata) }
}

public func buildCompactedHistory(
    initialContext: [ResponseItemEnvelope] = [],
    userMessages: [CompactedUserMessage],
    summaryText: String
) -> [ResponseItemEnvelope] {
    buildCompactedHistory(
        initialContext: initialContext,
        userMessages: userMessages,
        summaryText: summaryText,
        maxTokens: compactUserMessageMaxTokens
    )
}

public func buildCompactedHistory(
    initialContext: [ResponseItemEnvelope],
    userMessages: [CompactedUserMessage],
    summaryText: String,
    maxTokens: Int
) -> [ResponseItemEnvelope] {
    var history = initialContext
    var selected: [CompactedUserMessage] = []
    if maxTokens > 0 {
        var remaining = maxTokens
        for message in userMessages.reversed() {
            if remaining == 0 { break }
            let tokens = approxTokenCount(message.message)
            if tokens <= remaining {
                selected.append(message)
                remaining -= tokens
            } else {
                selected.append(
                    CompactedUserMessage(
                        id: message.id,
                        message: truncateTextByTokens(message.message, tokenBudget: remaining),
                        internalChatMessageMetadataPassthrough: message.internalChatMessageMetadataPassthrough,
                        harnessMetadata: message.harnessMetadata
                    )
                )
                break
            }
        }
        selected.reverse()
    }

    for message in selected {
        history.append(
            ResponseItemEnvelope(
                .message(
                    id: message.id,
                    role: "user",
                    content: [.inputText(text: message.message)],
                    phase: nil,
                    internalChatMessageMetadataPassthrough: message.internalChatMessageMetadataPassthrough
                ),
                metadata: message.harnessMetadata
            )
        )
    }

    let summary = summaryText.isEmpty ? compactNoSummaryAvailable : summaryText
    history.append(ResponseItemEnvelope(wrapCompactionSummary(summary)))
    return history
}

/// Codex `insert_initial_context_before_last_real_user_or_summary`.
public func insertInitialContextBeforeLastRealUserOrSummary(
    _ compactedHistory: [ResponseItemEnvelope],
    initialContext: [ResponseItemEnvelope]
) -> [ResponseItemEnvelope] {
    guard !initialContext.isEmpty else { return compactedHistory }
    var history = compactedHistory
    var lastUserOrSummaryIndex: Int?
    var lastRealUserIndex: Int?
    for index in history.indices.reversed() {
        let item = history[index].item
        guard item.isUserMessage() else { continue }
        if lastUserOrSummaryIndex == nil {
            lastUserOrSummaryIndex = index
        }
        if !isSummaryLikeUserMessage(item) {
            lastRealUserIndex = index
            break
        }
    }
    let lastCompactionIndex = history.indices.reversed().first { index in
        isCompactionHistoryItem(history[index].item)
    }
    if let insertionIndex = lastRealUserIndex ?? lastUserOrSummaryIndex ?? lastCompactionIndex {
        history.insert(contentsOf: initialContext, at: insertionIndex)
    } else {
        history.append(contentsOf: initialContext)
    }
    return history
}

func compactedUserMessage(
    _ item: ResponseItem,
    harnessMetadata: String?
) -> CompactedUserMessage? {
    if isGuardianContextMessage(item) { return nil }
    guard item.isUserMessage() else { return nil }
    if isCompactionSummaryItem(item) { return nil }
    guard case .message(let id, _, let content, _, let passthrough) = item,
          let text = contentItemsToText(content),
          !isSummaryMessage(text)
    else {
        return nil
    }
    return CompactedUserMessage(
        id: id,
        message: text,
        internalChatMessageMetadataPassthrough: passthrough,
        harnessMetadata: harnessMetadata
    )
}

func isCompactionSummaryItem(_ item: ResponseItem) -> Bool {
    guard case .message(_, _, _, _, let passthrough) = item else { return false }
    return passthrough?.contentItemKinds?.contains(ContentItemKind("compaction.summary")) == true
}

func isSummaryLikeUserMessage(_ item: ResponseItem) -> Bool {
    if isCompactionSummaryItem(item) { return true }
    guard case .message(_, _, let content, _, _) = item,
          let text = contentItemsToText(content)
    else { return false }
    return isSummaryMessage(text)
}

func isCompactionHistoryItem(_ item: ResponseItem) -> Bool {
    switch item {
    case .compaction, .contextCompaction, .compactionTrigger:
        return true
    default:
        return false
    }
}
