//
//  compact_remote_history.swift
//  CodexCore
//
//  Port of codex-rs/core/src/compact_remote_history.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import CodexProtocol
import CodexUtils
import Foundation

public let contextWindowTruncatedOutputMessage =
    "Output exceeded the available model context and was truncated"

public struct HistoryItemGroup<T>: Equatable, Sendable where T: Equatable & Sendable {
    public var source: T
    public var attachedNotice: T?

    public init(source: T, attachedNotice: T? = nil) {
        self.source = source
        self.attachedNotice = attachedNotice
    }

    public func intoItems() -> [T] {
        if let attachedNotice {
            return [source, attachedNotice]
        }
        return [source]
    }
}

public func historyItemGroups(_ items: [ResponseItemEnvelope]) -> [HistoryItemGroup<ResponseItemEnvelope>] {
    var groups: [HistoryItemGroup<ResponseItemEnvelope>] = []
    var index = 0
    while index < items.count {
        let source = items[index]
        var notice: ResponseItemEnvelope?
        if index + 1 < items.count, isAttachedNotice(items[index + 1].item) {
            notice = items[index + 1]
            index += 1
        }
        groups.append(HistoryItemGroup(source: source, attachedNotice: notice))
        index += 1
    }
    return groups
}

public func isAttachedNotice(_ item: ResponseItem) -> Bool {
    guard case .message(_, let role, let content, _, _) = item, role == "developer" else {
        return false
    }
    guard content.count == 1, case .inputText(let text) = content[0] else {
        return false
    }
    return text.contains("<image_resize_notice>")
}

public func estimatedGroupTokenCount(_ group: HistoryItemGroup<ResponseItemEnvelope>) -> Int {
    var tokens = estimateItemTokenCount(group.source.item)
    if let notice = group.attachedNotice {
        tokens += estimateItemTokenCount(notice.item)
    }
    return tokens
}

@discardableResult
public func trimFunctionCallHistoryToFitContextWindow(
    history: ContextManager,
    contextWindow: Int64?,
    baseInstructions: String
) -> (rewrittenOutputs: Int, estimatedDeletedTokens: Int) {
    guard let contextWindow else { return (0, 0) }
    let original = history.items
    var estimatedTokens = approxTokenCount(baseInstructions)
        + historyItemGroups(original).reduce(0) { $0 + estimatedGroupTokenCount($1) }
    let initialEstimatedTokens = estimatedTokens
    var rewritten: [ResponseItemEnvelope] = []
    var consumed = 0

    for group in historyItemGroups(original).reversed() {
        if estimatedTokens <= contextWindow { break }
        let groupItemCount = 1 + (group.attachedNotice == nil ? 0 : 1)
        let sourceIndex = original.count - consumed - groupItemCount
        guard sourceIndex >= 0, sourceIndex < original.count,
              let rewrittenItem = rewrittenOutputForContextWindow(original[sourceIndex])
        else { break }
        estimatedTokens = estimatedTokens
            - estimatedGroupTokenCount(group)
            + estimateItemTokenCount(rewrittenItem.item)
        consumed += groupItemCount
        rewritten.append(rewrittenItem)
    }

    if !rewritten.isEmpty {
        let retainedLen = original.count - consumed
        var items = Array(original.prefix(max(retainedLen, 0)))
        items.append(contentsOf: rewritten.reversed())
        history.replaceAnnotated(items)
    }
    return (rewritten.count, max(initialEstimatedTokens - estimatedTokens, 0))
}

func rewrittenOutputForContextWindow(_ envelope: ResponseItemEnvelope) -> ResponseItemEnvelope? {
    switch envelope.item {
    case .functionCallOutput(let id, let callId, let name, let namespace, let output, let meta):
        return ResponseItemEnvelope(
            .functionCallOutput(
                id: id,
                callId: callId,
                name: name,
                namespace: namespace,
                output: truncatedOutputPayload(output),
                internalChatMessageMetadataPassthrough: meta
            ),
            metadata: envelope.metadata
        )
    case .customToolCallOutput(let id, let callId, let name, let output, let meta):
        return ResponseItemEnvelope(
            .customToolCallOutput(
                id: id,
                callId: callId,
                name: name,
                output: truncatedOutputPayload(output),
                internalChatMessageMetadataPassthrough: meta
            ),
            metadata: envelope.metadata
        )
    case .toolSearchOutput(let id, let callId, let status, let execution, _, let meta):
        return ResponseItemEnvelope(
            .toolSearchOutput(
                id: id,
                callId: callId,
                status: status,
                execution: execution,
                tools: [],
                internalChatMessageMetadataPassthrough: meta
            ),
            metadata: envelope.metadata
        )
    default:
        return nil
    }
}

func truncatedOutputPayload(_ output: FunctionCallOutputPayload) -> FunctionCallOutputPayload {
    FunctionCallOutputPayload(body: .text(contextWindowTruncatedOutputMessage), success: output.success)
}
