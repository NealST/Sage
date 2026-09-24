//
//  cache_lib_tests.swift
//  SageTests
//
//  Port of codex-rs/utils/cache/src/lib.rs #[cfg(test)] (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  `disabled_without_runtime` is not ported: the upstream cache is a no-op
//  without a Tokio runtime, while the Swift port is always active (see
//  cache_lib.swift header).
//

import Foundation
import XCTest
@testable import CodexUtils

final class BlockingLruCacheTests: XCTestCase {

    /// `stores_and_retrieves_values`.
    func testStoresAndRetrievesValues() {
        let cache = BlockingLruCache<String, Int>(capacity: 2)

        XCTAssertNil(cache.get("first"))
        cache.insert("first", 1)
        XCTAssertEqual(cache.get("first"), 1)
    }

    /// `evicts_least_recently_used`.
    func testEvictsLeastRecentlyUsed() {
        let cache = BlockingLruCache<String, Int>(capacity: 2)
        cache.insert("a", 1)
        cache.insert("b", 2)
        XCTAssertEqual(cache.get("a"), 1)

        cache.insert("c", 3)

        XCTAssertNil(cache.get("b"))
        XCTAssertEqual(cache.get("a"), 1)
        XCTAssertEqual(cache.get("c"), 3)
    }
}
