//
//  compaction_summary.swift
//  CodexCore
//
//  Port of codex-rs/core/src/context/compaction_summary.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//

import CodexProtocol
import Foundation

public struct CompactionSummary: ContextualUserFragment, Equatable, Sendable {
    public var summary: String
    public init(summary: String) {
        self.summary = summary
    }
    public var contentKind: ContentItemKind { ContentItemKind("compaction.summary") }
    public var role: String { "user" }
    public var openMarker: String { "" }
    public var closeMarker: String { "" }
    public var body: String { summary }
}
