//
//  metadata_metrics.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/metadata_metrics.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  otel histograms wait for the trimmed metrics interface. The helper
//  still measures bytes shed by a metadata bound.
//

import CodexProtocol

func metadataBytes(_ items: [ResponseItem]) -> Int {
    items.reduce(0) { $0 + String(describing: $1).utf8.count }
}

func boundPromptMetadata(
    _ items: inout [ResponseItem],
    bound: (inout [ResponseItem]) -> Void
) -> Int {
    let before = metadataBytes(items)
    bound(&items)
    let after = metadataBytes(items)
    return before > after ? before - after : 0
}
