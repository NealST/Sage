//
//  inline_hidden_tag_tests.swift
//  SageTests
//
//  Port of codex-rs/utils/stream-parser/src/inline_hidden_tag.rs #[cfg(test)]
//  (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  Not ported: `generic_inline_parser_rejects_empty_open_delimiter` and
//  `generic_inline_parser_rejects_empty_close_delimiter` are `should_panic`
//  tests; XCTest cannot trap on the port's `precondition`.
//

import Foundation
import XCTest
@testable import CodexUtils

private enum Tag {
    case a
    case b
}

final class InlineHiddenTagParserTests: XCTestCase {

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

    /// `generic_inline_parser_supports_multiple_tag_types`.
    func testSupportsMultipleTagTypes() {
        let parser = InlineHiddenTagParser(specs: [
            InlineTagSpec(tag: Tag.a, open: "<a>", close: "</a>"),
            InlineTagSpec(tag: Tag.b, open: "<b>", close: "</b>"),
        ])

        let out = collectChunks(parser, ["1<a>x</a>2<b>y</b>3"])

        XCTAssertEqual(out.visibleText, "123")
        XCTAssertEqual(out.extracted.count, 2)
        XCTAssertEqual(out.extracted[0].tag, .a)
        XCTAssertEqual(out.extracted[0].content, "x")
        XCTAssertEqual(out.extracted[1].tag, .b)
        XCTAssertEqual(out.extracted[1].content, "y")
    }

    /// `generic_inline_parser_supports_non_ascii_tag_delimiters`.
    func testSupportsNonAsciiTagDelimiters() {
        let parser = InlineHiddenTagParser(specs: [
            InlineTagSpec(tag: Tag.a, open: "<é>", close: "</é>"),
        ])

        let out = collectChunks(parser, ["a<", "é>中</", "é>b"])

        XCTAssertEqual(out.visibleText, "ab")
        XCTAssertEqual(out.extracted.count, 1)
        XCTAssertEqual(out.extracted[0].tag, .a)
        XCTAssertEqual(out.extracted[0].content, "中")
    }

    /// `generic_inline_parser_prefers_longest_opener_at_same_offset`.
    func testPrefersLongestOpenerAtSameOffset() {
        let parser = InlineHiddenTagParser(specs: [
            InlineTagSpec(tag: Tag.a, open: "<a>", close: "</a>"),
            InlineTagSpec(tag: Tag.b, open: "<ab>", close: "</ab>"),
        ])

        let out = collectChunks(parser, ["x<ab>y</ab>z"])

        XCTAssertEqual(out.visibleText, "xz")
        XCTAssertEqual(out.extracted.count, 1)
        XCTAssertEqual(out.extracted[0].tag, .b)
        XCTAssertEqual(out.extracted[0].content, "y")
    }
}
