//
//  string_lib_tests.swift
//  SageTests
//
//  Port of codex-rs/utils/string/src/lib.rs #[cfg(test)] (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//

import Foundation
import XCTest
@testable import CodexUtils

final class StringLibTests: XCTestCase {

    /// `find_uuids_finds_multiple`.
    func testFindUuidsFindsMultiple() {
        let input =
            "x 00112233-4455-6677-8899-aabbccddeeff-k y 12345678-90ab-cdef-0123-456789abcdef"
        XCTAssertEqual(
            findUuids(input),
            [
                "00112233-4455-6677-8899-aabbccddeeff",
                "12345678-90ab-cdef-0123-456789abcdef",
            ]
        )
    }

    /// `find_uuids_ignores_invalid`.
    func testFindUuidsIgnoresInvalid() {
        let input = "not-a-uuid-1234-5678-9abc-def0-123456789abc"
        XCTAssertEqual(findUuids(input), [])
    }

    /// `find_uuids_handles_non_ascii_without_overlap`.
    func testFindUuidsHandlesNonAsciiWithoutOverlap() {
        let input = "🙂 55e5d6f7-8a7f-4d2a-8d88-123456789012abc"
        XCTAssertEqual(findUuids(input), ["55e5d6f7-8a7f-4d2a-8d88-123456789012"])
    }

    /// `sanitize_metric_tag_value_trims_and_fills_unspecified`.
    func testSanitizeMetricTagValueTrimsAndFillsUnspecified() {
        XCTAssertEqual(sanitizeMetricTagValue("///"), "unspecified")
    }

    /// `sanitize_metric_tag_value_replaces_invalid_chars`.
    func testSanitizeMetricTagValueReplacesInvalidChars() {
        XCTAssertEqual(sanitizeMetricTagValue("bad value!"), "bad_value")
    }

    /// `normalize_markdown_hash_location_suffix_converts_single_location`.
    func testNormalizeMarkdownHashLocationSuffixConvertsSingleLocation() {
        XCTAssertEqual(normalizeMarkdownHashLocationSuffix("#L74C3"), ":74:3")
    }

    /// `normalize_markdown_hash_location_suffix_converts_ranges`.
    func testNormalizeMarkdownHashLocationSuffixConvertsRanges() {
        XCTAssertEqual(normalizeMarkdownHashLocationSuffix("#L74C3-L76C9"), ":74:3-76:9")
    }
}
