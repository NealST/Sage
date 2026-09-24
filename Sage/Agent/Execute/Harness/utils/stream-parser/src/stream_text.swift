//
//  stream_text.swift
//  CodexUtils
//
//  Port of codex-rs/utils/stream-parser/src/stream_text.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  The `StreamTextParser` trait maps to a protocol. Parsers are stateful
//  `final class` types, so the protocol requirements are non-mutating.
//

import Foundation

/// Incremental parser result for one pushed chunk (or final flush).
public struct StreamTextChunk<Extracted> {
    /// Text safe to render immediately.
    public var visibleText: String
    /// Hidden payloads extracted from the chunk.
    public var extracted: [Extracted]

    /// `Default::default`.
    public init() {
        visibleText = ""
        extracted = []
    }

    /// Public fields mirror upstream's `pub struct` fields.
    public init(visibleText: String, extracted: [Extracted]) {
        self.visibleText = visibleText
        self.extracted = extracted
    }

    /// Returns true when no visible text or extracted payloads were produced.
    public var isEmpty: Bool {
        visibleText.isEmpty && extracted.isEmpty
    }
}

extension StreamTextChunk: Equatable where Extracted: Equatable {}

/// Trait for parsers that consume streamed text and emit visible text plus
/// extracted payloads.
public protocol StreamTextParser {
    /// Payload extracted by this parser (for example a citation body).
    associatedtype Extracted

    /// Feed a new text chunk.
    func pushStr(_ chunk: String) -> StreamTextChunk<Extracted>

    /// Flush any buffered state at end-of-stream (or end-of-item).
    func finish() -> StreamTextChunk<Extracted>
}
