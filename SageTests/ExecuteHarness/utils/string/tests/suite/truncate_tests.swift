//
//  truncate_tests.swift
//  SageTests
//
//  Port of codex-rs/utils/string/src/truncate/tests.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  `split_string` returns `(usize, &str, &str)`; the port returns
//  `(Int, Substring, Substring)` and tuple equality is spelled out per field.
//

import Foundation
import XCTest
@testable import CodexUtils

final class TruncateTests: XCTestCase {

    private func assertSplit(
        _ actual: (Int, Substring, Substring),
        _ expected: (Int, String, String),
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.0, expected.0, file: file, line: line)
        XCTAssertEqual(String(actual.1), expected.1, file: file, line: line)
        XCTAssertEqual(String(actual.2), expected.2, file: file, line: line)
    }

    /// `split_string_works`.
    func testSplitStringWorks() {
        assertSplit(
            splitString("hello world", beginningBytes: 5, endBytes: 5),
            (1, "hello", "world")
        )
        assertSplit(
            splitString("abc", beginningBytes: 0, endBytes: 0),
            (3, "", "")
        )
    }

    /// `split_string_handles_empty_string`.
    func testSplitStringHandlesEmptyString() {
        assertSplit(splitString("", beginningBytes: 4, endBytes: 4), (0, "", ""))
    }

    /// `split_string_only_keeps_prefix_when_tail_budget_is_zero`.
    func testSplitStringOnlyKeepsPrefixWhenTailBudgetIsZero() {
        assertSplit(splitString("abcdef", beginningBytes: 3, endBytes: 0), (3, "abc", ""))
    }

    /// `split_string_only_keeps_suffix_when_prefix_budget_is_zero`.
    func testSplitStringOnlyKeepsSuffixWhenPrefixBudgetIsZero() {
        assertSplit(splitString("abcdef", beginningBytes: 0, endBytes: 3), (3, "", "def"))
    }

    /// `split_string_handles_overlapping_budgets_without_removal`.
    func testSplitStringHandlesOverlappingBudgetsWithoutRemoval() {
        assertSplit(splitString("abcdef", beginningBytes: 4, endBytes: 4), (0, "abcd", "ef"))
    }

    /// `split_string_respects_utf8_boundaries`.
    func testSplitStringRespectsUtf8Boundaries() {
        assertSplit(
            splitString("😀abc😀", beginningBytes: 5, endBytes: 5),
            (1, "😀a", "c😀")
        )
        assertSplit(
            splitString("😀😀😀😀😀", beginningBytes: 1, endBytes: 1),
            (5, "", "")
        )
        assertSplit(
            splitString("😀😀😀😀😀", beginningBytes: 7, endBytes: 7),
            (3, "😀", "😀")
        )
        assertSplit(
            splitString("😀😀😀😀😀", beginningBytes: 8, endBytes: 8),
            (1, "😀😀", "😀😀")
        )
    }

    /// `truncate_with_token_budget_returns_original_when_under_limit`.
    func testTruncateWithTokenBudgetReturnsOriginalWhenUnderLimit() {
        let s = "short output"
        let (out, original) = truncateMiddleWithTokenBudget(s, maxTokens: 100)
        XCTAssertEqual(out, s)
        XCTAssertNil(original)
    }

    /// `truncate_with_token_budget_reports_truncation_at_zero_limit`.
    func testTruncateWithTokenBudgetReportsTruncationAtZeroLimit() {
        let (out, original) = truncateMiddleWithTokenBudget("abcdef", maxTokens: 0)
        XCTAssertEqual(out, "…2 tokens truncated…")
        XCTAssertEqual(original, 2)
    }

    /// `truncate_middle_tokens_handles_utf8_content`.
    func testTruncateMiddleTokensHandlesUtf8Content() {
        let s = "😀😀😀😀😀😀😀😀😀😀\nsecond line with text\n"
        let (out, tokens) = truncateMiddleWithTokenBudget(s, maxTokens: 8)
        XCTAssertEqual(out, "😀😀😀😀…8 tokens truncated… line with text\n")
        XCTAssertEqual(tokens, 16)
    }

    /// `truncate_middle_bytes_handles_utf8_content`.
    func testTruncateMiddleBytesHandlesUtf8Content() {
        let s = "😀😀😀😀😀😀😀😀😀😀\nsecond line with text\n"
        let out = truncateMiddleChars(s, maxBytes: 20)
        XCTAssertEqual(out, "😀😀…21 chars truncated…with text\n")
    }
}
