//
//  head_tail_buffer.swift
//  SageTests
//
//  Port of codex-rs/core/src/unified_exec/head_tail_buffer_tests.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//

@testable import CodexCore
import XCTest

final class HeadTailBufferTests: XCTestCase {
    func testKeepsPrefixAndSuffixWhenOverBudget() {
        var buf = HeadTailBuffer(maxBytes: 10)
        buf.pushChunk(Data("0123456789".utf8))
        XCTAssertEqual(buf.omittedBytes, 0)
        buf.pushChunk(Data("ab".utf8))
        XCTAssertGreaterThan(buf.omittedBytes, 0)
        let rendered = String(decoding: buf.toBytes(), as: UTF8.self)
        XCTAssertTrue(rendered.hasPrefix("01234"))
        XCTAssertTrue(rendered.hasSuffix("89ab"))
        XCTAssertEqual(
            String(decoding: buf.toBytesWithOmissionMarker(), as: UTF8.self),
            "01234\n... 2 bytes omitted ...\n789ab"
        )
    }

    func testMaxBytesZeroDropsEverything() {
        var buf = HeadTailBuffer(maxBytes: 0)
        buf.pushChunk(Data("abc".utf8))
        XCTAssertEqual(buf.retainedBytes, 0)
        XCTAssertEqual(buf.omittedBytes, 3)
        XCTAssertEqual(buf.toBytes(), Data())
    }

    func testHeadBudgetZeroKeepsOnlyLastByteInTail() {
        var buf = HeadTailBuffer(maxBytes: 1)
        buf.pushChunk(Data("abc".utf8))
        XCTAssertEqual(buf.retainedBytes, 1)
        XCTAssertEqual(buf.omittedBytes, 2)
        XCTAssertEqual(buf.toBytes(), Data("c".utf8))
    }

    func testFillsHeadThenTailAcrossMultipleChunks() {
        var buf = HeadTailBuffer(maxBytes: 10)
        buf.pushChunk(Data("01".utf8))
        buf.pushChunk(Data("234".utf8))
        XCTAssertEqual(buf.toBytes(), Data("01234".utf8))
        buf.pushChunk(Data("567".utf8))
        buf.pushChunk(Data("89".utf8))
        XCTAssertEqual(buf.toBytes(), Data("0123456789".utf8))
        XCTAssertEqual(buf.omittedBytes, 0)
        buf.pushChunk(Data("a".utf8))
        XCTAssertEqual(buf.toBytes(), Data("012346789a".utf8))
        XCTAssertEqual(buf.omittedBytes, 1)
    }
}
