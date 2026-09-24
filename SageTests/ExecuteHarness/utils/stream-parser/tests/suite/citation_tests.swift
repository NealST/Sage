//
//  citation_tests.swift
//  SageTests
//
//  Port of codex-rs/utils/stream-parser/src/citation.rs #[cfg(test)]
//  (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//

import Foundation
import XCTest
@testable import CodexUtils

final class CitationStreamParserTests: XCTestCase {

    private func collectChunks<P: StreamTextParser>(
        _ parser: P,
        _ chunks: [String]
    ) -> StreamTextChunk<P.Extracted> {
        var all = StreamTextChunk<P.Extracted>()
        for chunk in chunks {
            let next = parser.pushStr(chunk)
            all.visibleText += next.visibleText
            all.extracted.append(contentsOf: next.extracted)
        }
        let tail = parser.finish()
        all.visibleText += tail.visibleText
        all.extracted.append(contentsOf: tail.extracted)
        return all
    }

    /// `citation_parser_streams_across_chunk_boundaries`.
    func testStreamsAcrossChunkBoundaries() {
        let parser = CitationStreamParser()
        let out = collectChunks(parser, [
            "Hello <oai-mem-",
            "citation>source A</oai-mem-",
            "citation> world",
        ])

        XCTAssertEqual(out.visibleText, "Hello  world")
        XCTAssertEqual(out.extracted, ["source A"])
    }

    /// `citation_parser_buffers_partial_open_tag_prefix`.
    func testBuffersPartialOpenTagPrefix() {
        let parser = CitationStreamParser()

        let first = parser.pushStr("abc <oai-mem-")
        XCTAssertEqual(first.visibleText, "abc ")
        XCTAssertEqual(first.extracted, [])

        let second = parser.pushStr("citation>x</oai-mem-citation>z")
        let tail = parser.finish()

        XCTAssertEqual(second.visibleText, "z")
        XCTAssertEqual(second.extracted, ["x"])
        XCTAssertTrue(tail.isEmpty)
    }

    /// `citation_parser_auto_closes_unterminated_tag_on_finish`.
    func testAutoClosesUnterminatedTagOnFinish() {
        let parser = CitationStreamParser()
        let out = collectChunks(parser, ["x<oai-mem-citation>source"])

        XCTAssertEqual(out.visibleText, "x")
        XCTAssertEqual(out.extracted, ["source"])
    }

    /// `citation_parser_preserves_partial_open_tag_at_eof_if_not_a_full_tag`.
    func testPreservesPartialOpenTagAtEofIfNotAFullTag() {
        let parser = CitationStreamParser()
        let out = collectChunks(parser, ["hello <oai-mem-"])

        XCTAssertEqual(out.visibleText, "hello <oai-mem-")
        XCTAssertEqual(out.extracted, [])
    }

    /// `strip_citations_collects_all_citations`.
    func testStripCitationsCollectsAllCitations() {
        let (visible, citations) = stripCitations(
            "a<oai-mem-citation>one</oai-mem-citation>b<oai-mem-citation>two</oai-mem-citation>c"
        )

        XCTAssertEqual(visible, "abc")
        XCTAssertEqual(citations, ["one", "two"])
    }

    /// `strip_citations_auto_closes_unterminated_citation_at_eof`.
    func testStripCitationsAutoClosesUnterminatedCitationAtEof() {
        let (visible, citations) = stripCitations("x<oai-mem-citation>y")

        XCTAssertEqual(visible, "x")
        XCTAssertEqual(citations, ["y"])
    }

    /// `citation_parser_does_not_support_nested_tags`.
    func testDoesNotSupportNestedTags() {
        let (visible, citations) = stripCitations(
            "a<oai-mem-citation>x<oai-mem-citation>y</oai-mem-citation>z</oai-mem-citation>b"
        )

        XCTAssertEqual(visible, "az</oai-mem-citation>b")
        XCTAssertEqual(citations, ["x<oai-mem-citation>y"])
    }
}
