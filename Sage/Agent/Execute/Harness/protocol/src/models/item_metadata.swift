//
//  item_metadata.swift
//  CodexProtocol
//
//  Port of codex-rs/protocol/src/models/item_metadata.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  Harness-owned classification for one position in an item's content array.
//  Upstream tests (`item_metadata_tests.rs`) exercise `ResponseItem` from
//  `models.rs`; they land together with that file.
//

import Foundation

/// `ContentItemKind` — serde `transparent`, wire format is the bare string.
/// Unknown future values round-trip without restriction.
public struct ContentItemKind: Equatable, Sendable {
    public var value: String

    public init(_ value: String) {
        self.value = value
    }
}

extension ContentItemKind: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        value = try container.decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}
