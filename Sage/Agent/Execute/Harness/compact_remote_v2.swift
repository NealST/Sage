//
//  compact_remote_v2.swift
//  CodexCore
//
//  Port of codex-rs/core/src/compact_remote_v2.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  History grouping / retention / image-budget truncate are live.
//  Fallback-step retries the current model after a previous-model miss.
//

import CodexProtocol
import CodexUtils
import Foundation

public let retainedMessageTokenBudget = 64_000
public let maxRetainedAgentMessageTokens: Int64 = 10_000
public let maxRemoteCompactionV2StreamRetries: UInt64 = 2

public enum RetainedImageBudget: Equatable, Sendable {
    case disabled
    case enabled
}

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

public struct RemoteCompactionV2Output: Equatable, Sendable {
    public var compactionOutput: ResponseItem
    public var responseId: String
    public var tokenUsage: TokenUsage?
    public var summaryText: String

    public init(
        compactionOutput: ResponseItem,
        responseId: String,
        tokenUsage: TokenUsage? = nil,
        summaryText: String = ""
    ) {
        self.compactionOutput = compactionOutput
        self.responseId = responseId
        self.tokenUsage = tokenUsage
        self.summaryText = summaryText
    }
}

public func collectRemoteCompactSummary(from stream: ResponseStream) async throws -> String {
    try await collectRemoteCompactionV2Output(from: stream).summaryText
}

public func collectRemoteCompactionV2Output(from stream: ResponseStream) async throws -> RemoteCompactionV2Output {
    var outputItemCount = 0
    var compactionCount = 0
    var compactionOutput: ResponseItem?
    var lastAssistant = ""
    var completedResponseId: String?
    var completedTokenUsage: TokenUsage?
    for await event in stream.events {
        switch event {
        case .success(.outputItemDone(let item)):
            outputItemCount += 1
            if case .compaction = item {
                compactionCount += 1
                if compactionOutput == nil {
                    compactionOutput = item
                }
            }
            if let text = getLastAssistantMessage(from: [item]) {
                lastAssistant = text
            }
        case .success(.completed(let responseId, let tokenUsage, _, _)):
            completedResponseId = responseId
            completedTokenUsage = tokenUsage
        case .failure(let error):
            throw error
        default:
            break
        }
        if completedResponseId != nil { break }
    }
    guard let responseId = completedResponseId else {
        throw CodexErr.stream("remote compaction v2 stream closed before response.completed")
    }
    if compactionCount > 1 {
        throw CodexErr.fatal(
            "remote compaction v2 expected exactly one compaction output item, got \(compactionCount) from \(outputItemCount) output items"
        )
    }
    let output = compactionOutput ?? wrapCompactionSummary(lastAssistant)
    let summary = lastAssistant.isEmpty ? compactNoSummaryAvailable : lastAssistant
    return RemoteCompactionV2Output(
        compactionOutput: output,
        responseId: responseId,
        tokenUsage: completedTokenUsage,
        summaryText: summary
    )
}

public func isClientAuthoredDeveloperMessage(_ envelope: ResponseItemEnvelope) -> Bool {
    guard case .message(_, let role, _, _, _) = envelope.item, role == "developer" else {
        return false
    }
    return envelope.metadata == "client_authored"
}

public func isRetainedForRemoteCompactionV2(
    _ envelope: ResponseItemEnvelope,
    retainClientDeveloperMessages: Bool
) -> Bool {
    let item = envelope.item
    if case .agentMessage(_, let author, let recipient, let content, _) = item {
        let firstText: String? = {
            if case .inputText(let text) = content.first { return text }
            return nil
        }()
        let isDescendantProgress = author.hasPrefix(recipient)
            && author.dropFirst(recipient.count).first == "/"
            && (firstText?.hasPrefix("Message Type: MESSAGE\n") == true
                || firstText?.hasPrefix("Message Type: CHANNEL_POST\n") == true)
        let isCompletion = firstText?.hasPrefix("Message Type: FINAL_ANSWER\n") == true
        return !isDescendantProgress
            && !isCompletion
            && estimateItemTokenCount(item) <= Int(maxRetainedAgentMessageTokens)
    }
    guard case .message(_, let role, _, _, _) = item else { return false }
    switch role {
    case "user":
        if let parsed = parseTurnItem(item) {
            if case .userMessage = parsed { return true }
            if case .hookPrompt = parsed { return true }
        }
        return false
    case "developer":
        return retainClientDeveloperMessages && isClientAuthoredDeveloperMessage(envelope)
    default:
        return false
    }
}

public func retainedInputImageCount(_ item: ResponseItem) -> Int {
    guard case .message(_, _, let content, _, _) = item else { return 0 }
    return content.reduce(0) { count, part in
        if case .inputImage = part { return count + 1 }
        return count
    }
}

public func v2HistoryItemGroups(_ items: [ResponseItemEnvelope]) -> [HistoryItemGroup<ResponseItemEnvelope>] {
    historyItemGroups(items).flatMap { group in
        if let notice = group.attachedNotice, isClientAuthoredDeveloperMessage(notice) {
            return [
                HistoryItemGroup(source: group.source, attachedNotice: nil),
                HistoryItemGroup(source: notice, attachedNotice: nil),
            ]
        }
        return [group]
    }
}

public func truncateRetainedMessagesForRemoteCompaction(
    _ items: [ResponseItemEnvelope],
    maxTokens: Int = retainedMessageTokenBudget
) -> [ResponseItemEnvelope] {
    truncateRetainedMessages(items, maxTokens: maxTokens, imageBudget: .disabled)
}

public func truncateRetainedMessages(
    _ items: [ResponseItemEnvelope],
    maxTokens: Int,
    imageBudget: RetainedImageBudget
) -> [ResponseItemEnvelope] {
    var remaining = maxTokens
    var reversed: [ResponseItemEnvelope] = []
    for group in v2HistoryItemGroups(items).reversed() {
        if remaining == 0 { continue }
        let clientDeveloper = isClientAuthoredDeveloperMessage(group.source)
        let chargeImages = imageBudget == .enabled && !clientDeveloper
        let noticeTokens = group.attachedNotice.map { max(messageTextTokenCount($0.item), 1) } ?? 0
        let contentTokens = chargeImages
            ? messageContentTokenCount(group.source.item)
            : messageTextTokenCount(group.source.item)
        let sourceTokens = clientDeveloper
            ? estimateItemTokenCount(group.source.item)
            : max(contentTokens, 1)
        let tokenCount = sourceTokens + noticeTokens
        if tokenCount <= remaining {
            if let notice = group.attachedNotice {
                reversed.append(notice)
            }
            reversed.append(group.source)
            remaining -= tokenCount
            continue
        }
        guard remaining > noticeTokens else { continue }
        let available = remaining - noticeTokens
        let imageCount = retainedInputImageCount(group.source.item)
        if chargeImages, imageCount > 0 {
            remaining = 0
        }
        let truncated: ResponseItemEnvelope?
        if chargeImages, imageCount > 0 {
            truncated = truncateMessageToTokenBudget(group.source, maxTokens: available)
        } else {
            truncated = truncateMessageTextToTokenBudget(group.source, maxTokens: available)
        }
        guard let truncated else { continue }
        if let notice = group.attachedNotice {
            reversed.append(notice)
        }
        reversed.append(truncated)
        remaining = 0
    }
    return reversed.reversed()
}

public func buildV2CompactedHistory(
    promptInput: [ResponseItemEnvelope],
    compactionOutput: ResponseItem,
    retainClientDeveloperMessages: Bool = false,
    imageBudget: RetainedImageBudget = .disabled
) -> [ResponseItemEnvelope] {
    let retained = v2HistoryItemGroups(promptInput)
        .filter { isRetainedForRemoteCompactionV2($0.source, retainClientDeveloperMessages: retainClientDeveloperMessages) }
        .flatMap { $0.intoItems() }
    var truncated = truncateRetainedMessages(retained, maxTokens: retainedMessageTokenBudget, imageBudget: imageBudget)
    truncated.append(ResponseItemEnvelope(compactionOutput))
    return truncated
}

func messageTextTokenCount(_ item: ResponseItem) -> Int {
    approxTokenCount(contentItemsToText(messageContent(item)) ?? "")
}

func messageContentTokenCount(_ item: ResponseItem) -> Int {
    messageContent(item).reduce(0) { $0 + contentItemTokenCount($1) }
}

func messageContent(_ item: ResponseItem) -> [ContentItem] {
    if case .message(_, _, let content, _, _) = item { return content }
    return []
}

func truncateMessageTextToTokenBudget(
    _ envelope: ResponseItemEnvelope,
    maxTokens: Int
) -> ResponseItemEnvelope? {
    guard case .message(let id, let role, let content, let phase, let meta) = envelope.item else {
        return envelope
    }
    let text = contentItemsToText(content) ?? ""
    let truncated = truncateTextByTokens(text, tokenBudget: maxTokens)
    if truncated.isEmpty { return nil }
    return ResponseItemEnvelope(
        .message(
            id: id,
            role: role,
            content: [.inputText(text: truncated)],
            phase: phase,
            internalChatMessageMetadataPassthrough: meta
        ),
        metadata: envelope.metadata
    )
}
