//
//  lib_tests.swift
//  SageTests
//
//  Port of codex-rs/async-utils/src/lib.rs #[cfg(test)] (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  `tokio::time::sleep` maps to `Task.sleep`. `task::spawn` maps to an
//  unstructured `Task`.
//

import Foundation
import XCTest
@testable import CodexAsyncUtils

final class OrCancelTests: XCTestCase {

    /// `returns_ok_when_future_completes_first`.
    func testReturnsOkWhenFutureCompletesFirst() async {
        let token = CancellationToken()

        let result = await orCancel(token) { 42 }

        XCTAssertEqual(result, .success(42))
    }

    /// `returns_err_when_token_cancelled_first`.
    func testReturnsErrWhenTokenCancelledFirst() async {
        let token = CancellationToken()

        let cancelHandle = Task {
            try? await Task.sleep(nanoseconds: 10_000_000)
            token.cancel()
        }

        let result = await orCancel(token) { () async -> Int in
            try? await Task.sleep(nanoseconds: 100_000_000)
            return 7
        }

        await cancelHandle.value
        XCTAssertEqual(result, .failure(.cancelled))
    }

    /// `returns_err_when_token_already_cancelled`.
    func testReturnsErrWhenTokenAlreadyCancelled() async {
        let token = CancellationToken()
        token.cancel()

        let result = await orCancel(token) { () async -> Int in
            try? await Task.sleep(nanoseconds: 50_000_000)
            return 5
        }

        XCTAssertEqual(result, .failure(.cancelled))
    }
}
