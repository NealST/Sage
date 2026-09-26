//
//  node_repl_review_evidence.swift
//  CodexCore
//
//  Port of codex-rs/core/src/context/node_repl_review_evidence.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import CodexProtocol
import Foundation

public enum NodeReplReviewEvidenceMode: String, Equatable, Sendable {
    case include
    case omit
}

public func nodeReplReviewEvidenceMode(includeEvidence: Bool) -> NodeReplReviewEvidenceMode {
    includeEvidence ? .include : .omit
}

public struct NodeReplReviewEvidence: ContextualUserFragment, Equatable, Sendable {
    public var mode: NodeReplReviewEvidenceMode
    public var text: String

    public init(mode: NodeReplReviewEvidenceMode, text: String) {
        self.mode = mode
        self.text = text
    }

    public var contentKind: ContentItemKind { ContentItemKind("guardian.node_repl_review_evidence") }
    public var role: String { "developer" }
    public var openMarker: String { "<node_repl_review_evidence>" }
    public var closeMarker: String { "</node_repl_review_evidence>" }
    public var body: String {
        mode == .omit ? "Node REPL evidence omitted." : text
    }
}
