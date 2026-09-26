//
//  normalize.swift
//  CodexCore
//
//  Port of codex-rs/core/src/context_manager/normalize.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Synthetic output IDs stay deterministic. Image/audio modality rewriting
//  is limited to inserting aborted outputs for missing tool results.
//

import CodexProtocol
import Foundation

public func ensureCallOutputsPresent(_ items: inout [ResponseItemEnvelope]) {
    var functionOutputIds = Set<String>()
    var toolSearchOutputIds = Set<String>()
    var customToolOutputIds = Set<String>()
    for envelope in items {
        switch envelope.item {
        case .functionCallOutput(_, let callId, _, _, _, _):
            if let callId { functionOutputIds.insert(callId) }
        case .toolSearchOutput(_, let callId, _, _, _, _):
            if let callId { toolSearchOutputIds.insert(callId) }
        case .customToolCallOutput(_, let callId, _, _, _):
            customToolOutputIds.insert(callId)
        default:
            break
        }
    }

    var insertions: [(Int, ResponseItemEnvelope)] = []
    for (idx, envelope) in items.enumerated() {
        switch envelope.item {
        case .functionCall(let id, _, _, _, _, let callId, _):
            if !functionOutputIds.contains(callId) {
                insertions.append((
                    idx,
                    ResponseItemEnvelope(.functionCallOutput(
                        id: syntheticOutputId("fco", id),
                        callId: callId,
                        name: nil,
                        namespace: nil,
                        output: FunctionCallOutputPayload.fromText("aborted"),
                        internalChatMessageMetadataPassthrough: nil
                    ))
                ))
            }
        case .toolSearchCall(let id, let callId, _, _, _, _):
            if let callId, !toolSearchOutputIds.contains(callId) {
                insertions.append((
                    idx,
                    ResponseItemEnvelope(.toolSearchOutput(
                        id: syntheticOutputId("tso", id),
                        callId: callId,
                        status: "completed",
                        execution: "aborted",
                        tools: [],
                        internalChatMessageMetadataPassthrough: nil
                    ))
                ))
            }
        case .customToolCall(let id, _, let callId, _, _, _, _):
            if !customToolOutputIds.contains(callId) {
                insertions.append((
                    idx,
                    ResponseItemEnvelope(.customToolCallOutput(
                        id: syntheticOutputId("cto", id),
                        callId: callId,
                        name: nil,
                        output: FunctionCallOutputPayload.fromText("aborted"),
                        internalChatMessageMetadataPassthrough: nil
                    ))
                ))
            }
        default:
            break
        }
    }

    for (idx, item) in insertions.reversed() {
        items.insert(item, at: idx + 1)
    }
}

func syntheticOutputId(_ prefix: String, _ source: ResponseItemId?) -> ResponseItemId {
    if let source {
        return ResponseItemId.fromServer("\(prefix)_\(source.description)")
    }
    return ResponseItemId(new: prefix)
}
