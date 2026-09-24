//
//  utf8_stream_tests.swift
//  SageTests
//
//  Port of codex-rs/utils/stream-parser/src/utf8_stream.rs #[cfg(test)]
//  (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  `&[u8]` chunks map to `[UInt8]`; `Result::unwrap`/`expect` map to
//  `try`/`XCTUnwrap`-style assertions.
//

import Foundation
import XCTest
@testable import CodexUtils

final class Utf8StreamParserTests: XCTestCase {

    private func collectBytes(
        _ parser: Utf8StreamParser<CitationStreamParser>,
        _ chunks: [[UInt8]]
    ) throws -> StreamTextChunk<String> {
        var all = StreamTextChunk<String>()
        for chunk in chunks {
            let next = try parser.pushBytes(chunk)
            all.visibleText += next.visibleText
            all.extracted.append(contentsOf: next.extracted)
        }
        let tail = try parser.finish()
        all.visibleText += tail.visibleText
        all.extracted.append(contentsOf: tail.extracted)
        return all
    }

    /// `utf8_stream_parser_handles_split_code_points_across_chunks`.
    func testHandlesSplitCodePointsAcrossChunks() throws {
        let chunks: [[UInt8]] = [
            [0x41, 0xC3], // "A" + first byte of é
            [0xA9] + Array("<oai-mem-citation>".utf8) + [0xE4],
            [0xB8, 0xAD] + Array("</oai-mem-citation>".utf8) + [0x5A], // "中" split + "Z"
        ]

        let parser = Utf8StreamParser(inner: CitationStreamParser())
        let out = try collectBytes(parser, chunks)

        XCTAssertEqual(out.visibleText, "AéZ")
        XCTAssertEqual(out.extracted, ["中"])
    }

    /// `utf8_stream_parser_rolls_back_on_invalid_utf8_chunk`.
    func testRollsBackOnInvalidUtf8Chunk() throws {
        let parser = Utf8StreamParser(inner: CitationStreamParser())

        let first = try parser.pushBytes([0xC3])
        XCTAssertTrue(first.isEmpty)

        do {
            let out = try parser.pushBytes([0x28])
            XCTFail("invalid continuation byte should error, got output: \(out)")
        } catch {
            XCTAssertEqual(
                error as? Utf8StreamParserError,
                .invalidUtf8(validUpTo: 0, errorLen: 1)
            )
        }

        let second = try parser.pushBytes([0xA9, 0x78])
        let tail = try parser.finish()

        XCTAssertEqual(second.visibleText, "éx")
        XCTAssertTrue(second.extracted.isEmpty)
        XCTAssertTrue(tail.isEmpty)
    }

    /// `utf8_stream_parser_rolls_back_entire_chunk_when_invalid_byte_follows_valid_prefix`.
    func testRollsBackEntireChunkWhenInvalidByteFollowsValidPrefix() throws {
        let parser = Utf8StreamParser(inner: CitationStreamParser())

        do {
            let out = try parser.pushBytes(Array("ok".utf8) + [0xFF])
            XCTFail("invalid byte should error, got output: \(out)")
        } catch {
            XCTAssertEqual(
                error as? Utf8StreamParserError,
                .invalidUtf8(validUpTo: 2, errorLen: 1)
            )
        }

        let next = try parser.pushBytes(Array("!".utf8))
        XCTAssertEqual(next.visibleText, "!")
        XCTAssertTrue(next.extracted.isEmpty)
    }

    /// `utf8_stream_parser_errors_on_incomplete_code_point_at_eof`.
    func testErrorsOnIncompleteCodePointAtEof() throws {
        let parser = Utf8StreamParser(inner: CitationStreamParser())

        let out = try parser.pushBytes([0xE2, 0x82])
        XCTAssertTrue(out.isEmpty)

        do {
            let out = try parser.finish()
            XCTFail("unfinished code point should error, got output: \(out)")
        } catch {
            XCTAssertEqual(error as? Utf8StreamParserError, .incompleteUtf8AtEof)
        }
    }

    /// `utf8_stream_parser_into_inner_errors_when_partial_code_point_is_buffered`.
    func testIntoInnerErrorsWhenPartialCodePointIsBuffered() throws {
        let parser = Utf8StreamParser(inner: CitationStreamParser())

        let out = try parser.pushBytes([0xC3])
        XCTAssertTrue(out.isEmpty)

        do {
            _ = try parser.intoInner()
            XCTFail("buffered partial code point should be rejected")
        } catch {
            XCTAssertEqual(error as? Utf8StreamParserError, .incompleteUtf8AtEof)
        }
    }

    /// `utf8_stream_parser_into_inner_lossy_drops_buffered_partial_code_point`.
    func testIntoInnerLossyDropsBufferedPartialCodePoint() throws {
        let parser = Utf8StreamParser(inner: CitationStreamParser())

        let out = try parser.pushBytes([0xC3])
        XCTAssertTrue(out.isEmpty)

        let inner = parser.intoInnerLossy()
        let tail = inner.finish()
        XCTAssertTrue(tail.isEmpty)
    }
}
