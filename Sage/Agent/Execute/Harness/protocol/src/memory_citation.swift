//
//  memory_citation.swift
//  CodexProtocol
//
//  Port of codex-rs/protocol/src/memory_citation.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  Memory citations attached to assistant output; serde camelCase keys map to
//  explicit `CodingKeys`.
//

import Foundation

public struct MemoryCitation: Equatable, Sendable {
    public var entries: [MemoryCitationEntry]
    public var rolloutIds: [String]

    public init(entries: [MemoryCitationEntry] = [], rolloutIds: [String] = []) {
        self.entries = entries
        self.rolloutIds = rolloutIds
    }
}

extension MemoryCitation: Codable {
    // serde camelCase: wire keys are `entries` / `rolloutIds` — identical to
    // the Swift property names, so synthesized Codable is exact.
}

public struct MemoryCitationEntry: Equatable, Sendable {
    public var path: String
    public var lineStart: UInt32
    public var lineEnd: UInt32
    public var note: String

    public init(path: String, lineStart: UInt32, lineEnd: UInt32, note: String) {
        self.path = path
        self.lineStart = lineStart
        self.lineEnd = lineEnd
        self.note = note
    }
}

extension MemoryCitationEntry: Codable {
    // serde camelCase: wire keys match the Swift property names.
}
