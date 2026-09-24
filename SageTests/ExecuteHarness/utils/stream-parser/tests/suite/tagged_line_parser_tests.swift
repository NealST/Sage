//
//  tagged_line_parser_tests.swift
//  SageTests
//
//  Port of codex-rs/utils/stream-parser/src/tagged_line_parser.rs #[cfg(test)]
//  (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//

import Foundation
import XCTest
@testable import CodexUtils

private enum Tag {
    case block
}

final class TaggedLineParserTests: XCTestCase {

    private func parser() -> TaggedLineParser<Tag> {
        TaggedLineParser(specs: [TagSpec(open: "<tag>", close: "</tag>", tag: .block)])
    }

    /// `buffers_prefix_until_tag_is_decided`.
    func testBuffersPrefixUntilTagIsDecided() {
        let parser = parser()
        var segments = parser.parse("<t")
        segments.append(contentsOf: parser.parse("ag>\nline\n</tag>\n"))
        segments.append(contentsOf: parser.finish())

        XCTAssertEqual(
            segments,
            [
                .tagStart(.block),
                .tagDelta(.block, "line\n"),
                .tagEnd(.block),
            ]
        )
    }

    /// `rejects_tag_lines_with_extra_text`.
    func testRejectsTagLinesWithExtraText() {
        let parser = parser()
        var segments = parser.parse("<tag> extra\n")
        segments.append(contentsOf: parser.finish())

        XCTAssertEqual(segments, [.normal("<tag> extra\n")])
    }
}
