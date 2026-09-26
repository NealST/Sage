//
//  client_tool_metadata.swift
//  CodexCore
//
//  Port of codex-rs/core/src/client_tool_metadata.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  otel shedding metrics are omitted (Phase 10). Byte counts use
//  serializedJSONBytes. metadata_metrics lives in the Sage app module,
//  so this file uses the protocol bound helper plus a local byte count.
//

import CodexProtocol
import CodexUtils
import Foundation

let maxResponseMessageBytes = 15 * 1024 * 1024

func boundedInput<T: Encodable>(
    message: T,
    input: [ResponseItem]
) -> [ResponseItem]? {
    let hasMetadata = input.contains { item in
        guard let metadata = item.executedToolCallMetadata() else { return false }
        return metadata.executedToolCalls != nil
            || metadata.cellId != nil
            || metadata.toolCallsComplete != nil
    }
    guard hasMetadata else { return nil }
    guard let messageBytes = try? serializedJSONBytes(message) else { return nil }
    guard messageBytes > maxResponseMessageBytes else { return nil }
    let before = input.reduce(0) { $0 + executedToolCallMetadataBytes($1) }
    var bounded = input
    let overage = messageBytes - maxResponseMessageBytes
    boundExecutedToolCallsForMessage(&bounded, maxMetadataBytes: max(0, before - overage))
    let after = bounded.reduce(0) { $0 + executedToolCallMetadataBytes($1) }
    if before == after { return nil }
    return bounded
}
