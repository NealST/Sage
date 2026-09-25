//
//  error.swift
//  SageTests
//
//  Port of selected cases from codex-rs/protocol/src/error_tests.rs
//  (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//

import Foundation
import XCTest
@testable import CodexProtocol

final class CodexErrorTests: XCTestCase {
    func testUsageLimitReachedFormatsPlusPlan() {
        let error = UsageLimitReachedError(
            planType: .known(.plus),
            resetsAt: nil,
            rateLimits: RateLimitSnapshot(),
            promoMessage: nil,
            rateLimitReachedType: nil)
        XCTAssertEqual(
            error.description,
            "You’ve hit your usage limit. Upgrade to Pro (https://chatgpt.com/explore/pro), visit https://chatgpt.com/codex/settings/usage to purchase more credits or try again later.")
    }

    func testServerOverloadedMapsToProtocol() {
        XCTAssertEqual(CodexErr.new(.serverOverloaded).toCodexProtocolError(), .serverOverloaded)
    }

    func testSandboxDeniedUsesAggregatedOutput() {
        let output = ExecToolCallOutput(
            exitCode: 77,
            stdout: .new(""),
            stderr: .new(""),
            aggregatedOutput: .new("aggregate detail"),
            duration: .milliseconds(10),
            timedOut: false)
        let error = CodexErr.sandbox(.denied(output: output, networkPolicyDecision: nil))
        XCTAssertEqual(getErrorMessageUi(error), "aggregate detail")
    }
}
