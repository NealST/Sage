//
//  history.swift
//  CodexCore
//
//  Port of codex-rs/core/src/context_manager/history.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Guardian review transcripts and retained-context SHA wait. Item
//  recording, replacement, token-info, and model-visible-byte estimates
//  are ported. Original-detail images use PNG/JPEG/GIF headers.
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

    public func forPrompt(inputModalities: [InputModality] = []) -> [ResponseItem] {
        _ = inputModalities
        return items.map(\.item)
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
    Int(clamping: approxTokensFromByteCountI64(estimateResponseItemModelVisibleBytes(item)))
}

public func estimateImageReferenceBytes(_ item: ResponseItem) -> Int {
    Int(clamping: imageReferenceBytes(in: item))
}

func estimateResponseItemModelVisibleBytes(_ item: ResponseItem) -> Int64 {
    switch item {
    case .message(_, _, let content, _, _):
        return content.reduce(0 as Int64) { partial, part in
            saturatingAddInt64(partial, contentItemModelVisibleBytes(part))
        }
    case .agentMessage(_, let author, let recipient, let content, _):
        return content.reduce(saturatingAddInt64(textBytes(author), textBytes(recipient))) { partial, part in
            switch part {
            case .inputText(let text):
                return saturatingAddInt64(partial, textBytes(text))
            case .encryptedContent(let encrypted):
                return saturatingAddInt64(
                    partial,
                    Int64(clamping: estimateEncryptedFunctionOutputLength(encrypted.utf8.count))
                )
            }
        }
    case .reasoning(_, _, _, let encrypted, _) where encrypted != nil:
        return Int64(clamping: estimateReasoningLength(encrypted!.utf8.count))
    case .compaction(_, let encrypted, _):
        return Int64(clamping: estimateReasoningLength(encrypted.utf8.count))
    case .contextCompaction(_, let encrypted, _) where encrypted != nil:
        return Int64(clamping: estimateReasoningLength(encrypted!.utf8.count))
    case .functionCall(_, let name, let namespace, let arguments, _, _, _):
        return saturatingAddInt64(
            saturatingAddInt64(textBytes(name), textBytes(namespace ?? DEFAULT_FUNCTION_NAMESPACE)),
            textBytes(arguments)
        )
    case .customToolCall(_, _, _, let name, let namespace, let input, _):
        return saturatingAddInt64(
            saturatingAddInt64(textBytes(name), textBytes(namespace ?? DEFAULT_FUNCTION_NAMESPACE)),
            textBytes(input)
        )
    case .functionCallOutput(_, let callId, let name, let namespace, let output, _):
        return saturatingAddInt64(
            saturatingAddInt64(
                saturatingAddInt64(estimateFunctionOutputBytes(output.body), textBytes(callId ?? "")),
                textBytes(name ?? "")
            ),
            textBytes(namespace ?? "")
        )
    case .customToolCallOutput(_, let callId, let name, let output, _):
        return saturatingAddInt64(
            saturatingAddInt64(estimateFunctionOutputBytes(output.body), textBytes(callId)),
            textBytes(name ?? "")
        )
    case .additionalTools(_, _, let tools):
        return jsonContentBytes(tools)
    case .toolSearchCall(_, _, _, _, let arguments, _):
        return jsonContentBytes(arguments)
    case .toolSearchOutput(_, _, _, _, let tools, _):
        return jsonContentBytes(tools)
    case .localShellCall(_, _, _, let action, _):
        return jsonContentBytes(action)
    case .webSearchCall(_, _, let action, _):
        return action.map(jsonContentBytes) ?? 0
    case .imageGenerationCall(_, _, let revisedPrompt, let result, _):
        let imageBytes: Int64 = result.isEmpty ? 0 : Int64(resizedImageBytesEstimate)
        return saturatingAddInt64(textBytes(revisedPrompt ?? ""), imageBytes)
    case .contextCompaction(_, nil, _),
         .reasoning(_, _, _, nil, _),
         .configurationUpdate,
         .compactionTrigger,
         .other:
        return 0
    default:
        return 0
    }
}

func contentItemModelVisibleBytes(_ item: ContentItem) -> Int64 {
    switch item {
    case .inputText(let text), .outputText(let text):
        return textBytes(text)
    case .inputImage(let image, let detail):
        return Int64(clamping: estimateImageReferenceBytes(image, detail: detail))
    case .inputAudio(let audioURL):
        return estimateAudioBytes(audioURL)
    }
}

func estimateFunctionOutputBytes(_ output: FunctionCallOutputBody) -> Int64 {
    switch output {
    case .text(let text):
        return textBytes(text)
    case .contentItems(let items):
        return items.reduce(0 as Int64) { partial, part in
            saturatingAddInt64(partial, functionCallOutputContentBytes(part))
        }
    }
}

func functionCallOutputContentBytes(_ item: FunctionCallOutputContentItem) -> Int64 {
    switch item {
    case .inputText(let text):
        return textBytes(text)
    case .inputImage(let image, let detail):
        return Int64(clamping: estimateImageReferenceBytes(image, detail: detail))
    case .inputAudio(let audioURL):
        return estimateAudioBytes(audioURL)
    case .encryptedContent(let encrypted):
        return Int64(clamping: estimateEncryptedFunctionOutputLength(encrypted.utf8.count))
    }
}

func imageReferenceBytes(in item: ResponseItem) -> Int64 {
    switch item {
    case .message(_, _, let content, _, _):
        return content.reduce(0 as Int64) { partial, part in
            if case .inputImage(let image, let detail) = part {
                return saturatingAddInt64(
                    partial,
                    Int64(clamping: estimateImageReferenceBytes(image, detail: detail))
                )
            }
            return partial
        }
    case .functionCallOutput(_, _, _, _, let output, _),
         .customToolCallOutput(_, _, _, let output, _):
        if case .contentItems(let items) = output.body {
            return items.reduce(0 as Int64) { partial, part in
                if case .inputImage(let image, let detail) = part {
                    return saturatingAddInt64(
                        partial,
                        Int64(clamping: estimateImageReferenceBytes(image, detail: detail))
                    )
                }
                return partial
            }
        }
        return 0
    case .imageGenerationCall(_, _, _, let result, _) where !result.isEmpty:
        return Int64(resizedImageBytesEstimate)
    default:
        return 0
    }
}

func estimateAudioBytes(_ audioURL: String) -> Int64 {
    Int64(clamping: approxBytesForTokens(estimateAudioTokenCount(audioURL)))
}

func estimateReasoningLength(_ encodedLen: Int) -> Int {
    let (tripled, overflow) = encodedLen.multipliedReportingOverflow(by: 3)
    if overflow { return Int.max }
    return max(0, tripled / 4 - 650)
}

func estimateEncryptedFunctionOutputLength(_ encodedLen: Int) -> Int {
    let (nines, overflow) = encodedLen.multipliedReportingOverflow(by: 9)
    if overflow { return Int.max }
    return (nines + 15) / 16
}

func textBytes(_ text: String) -> Int64 {
    Int64(clamping: text.utf8.count)
}

func jsonContentBytes(_ value: JSONValue) -> Int64 {
    Int64(clamping: value.encodedString().utf8.count)
}

func jsonContentBytes<T: Encodable>(_ value: T) -> Int64 {
    (try? serializedJSONBytes(value)).map { Int64(clamping: $0) } ?? 0
}

func saturatingAddInt64(_ lhs: Int64, _ rhs: Int64) -> Int64 {
    let (result, overflow) = lhs.addingReportingOverflow(rhs)
    if overflow { return lhs >= 0 ? .max : .min }
    return result
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
