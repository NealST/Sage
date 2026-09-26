//
//  memory.swift
//  CodexCore
//
//  Port of codex-rs/core/src/context/memory.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import CodexProtocol
import CodexUtils
import Foundation

public enum MemoryContextFragment: ContextualUserFragment, Equatable, Sendable {
    case readInstructions(String)
    case extractionEvidence(String)

    public var role: String {
        switch self {
        case .readInstructions: return "developer"
        case .extractionEvidence: return "user"
        }
    }

    public var contentKind: ContentItemKind {
        switch self {
        case .readInstructions: return ContentItemKind("memories.instructions")
        case .extractionEvidence: return ContentItemKind("memories.extraction_evidence")
        }
    }

    public var requiresSeparateMessage: Bool { true }
    public var openMarker: String { "" }
    public var closeMarker: String { "" }

    public var body: String {
        let text: String
        switch self {
        case .readInstructions(let value), .extractionEvidence(let value):
            text = value
        }
        return truncateTextByBytes(text, budget: 8_900)
    }
}
