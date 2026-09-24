//
//  citation.swift
//  CodexUtils
//
//  Port of codex-rs/utils/stream-parser/src/citation.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//

import Foundation

private enum CitationTag {
    case citation
}

private let citationOpen = "<oai-mem-citation>"
private let citationClose = "</oai-mem-citation>"

/// Stream parser for `<oai-mem-citation>...</oai-mem-citation>` tags.
///
/// This is a thin convenience wrapper around `InlineHiddenTagParser`. It
/// returns citation bodies as plain strings and omits the citation tags from
/// visible text.
///
/// Matching is literal and non-nested. If EOF is reached before a closing
/// `</oai-mem-citation>`, the parser auto-closes the tag and returns the
/// buffered body as an extracted citation.
public final class CitationStreamParser {
    private let inner: InlineHiddenTagParser<CitationTag>

    public init() {
        inner = InlineHiddenTagParser(specs: [InlineTagSpec(
            tag: .citation,
            open: citationOpen,
            close: citationClose
        )])
    }
}

extension CitationStreamParser: StreamTextParser {
    public func pushStr(_ chunk: String) -> StreamTextChunk<String> {
        let inner = self.inner.pushStr(chunk)
        return StreamTextChunk(
            visibleText: inner.visibleText,
            extracted: inner.extracted.map(\.content)
        )
    }

    public func finish() -> StreamTextChunk<String> {
        let inner = self.inner.finish()
        return StreamTextChunk(
            visibleText: inner.visibleText,
            extracted: inner.extracted.map(\.content)
        )
    }
}

/// Strip citation tags from a complete string and return
/// `(visibleText, citations)`.
///
/// This uses `CitationStreamParser` internally, so it inherits the same
/// semantics: literal, non-nested matching and auto-closing unterminated
/// citations at EOF.
public func stripCitations(_ text: String) -> (visibleText: String, citations: [String]) {
    let parser = CitationStreamParser()
    var out = parser.pushStr(text)
    let tail = parser.finish()
    out.visibleText += tail.visibleText
    out.extracted.append(contentsOf: tail.extracted)
    return (out.visibleText, out.extracted)
}
