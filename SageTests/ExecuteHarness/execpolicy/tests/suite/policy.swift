//
//  policy.swift
//  SageTests
//
//  Port of codex-rs/execpolicy prefix-rule evaluation (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Exercises PolicyParser subset language and Decision aggregation.
//

import CodexExecPolicy
import XCTest

final class ExecPolicyTests: XCTestCase {
    func testPrefixRuleAllow() throws {
        let parser = PolicyParser()
        try parser.parse(
            policyIdentifier: "test.rules",
            policyFileContents: #"prefix_rule(pattern=["echo"], decision="allow")"#
        )
        let policy = parser.build()
        let evaluation = policy.check(["echo", "hi"]) { _ in .prompt }
        XCTAssertEqual(evaluation.decision, .allow)
        XCTAssertTrue(evaluation.isMatch())
    }

    func testStrictestDecisionWins() throws {
        let parser = PolicyParser()
        try parser.parse(
            policyIdentifier: "test.rules",
            policyFileContents: """
            prefix_rule(pattern=["git"], decision="allow")
            prefix_rule(pattern=["git", "push"], decision="forbidden")
            """
        )
        let policy = parser.build()
        let evaluation = policy.check(["git", "push", "origin"]) { _ in .prompt }
        XCTAssertEqual(evaluation.decision, .forbidden)
    }

    func testAlternativesAndExamples() throws {
        let parser = PolicyParser()
        try parser.parse(
            policyIdentifier: "test.rules",
            policyFileContents: """
            prefix_rule(
                pattern=["git", ["status", "diff"]],
                decision="allow",
                match=[["git", "status"], "git diff"],
                not_match=[["git", "push"]],
            )
            """
        )
        let policy = parser.build()
        XCTAssertEqual(policy.check(["git", "status"]) { _ in .prompt }.decision, .allow)
        XCTAssertEqual(policy.check(["git", "push"]) { _ in .prompt }.decision, .prompt)
    }

    func testNetworkRuleHostNormalization() throws {
        let parser = PolicyParser()
        try parser.parse(
            policyIdentifier: "test.rules",
            policyFileContents: #"network_rule(host="Api.GitHub.com", protocol="https", decision="allow")"#
        )
        let policy = parser.build()
        let (allowed, denied) = policy.compiledNetworkDomains()
        XCTAssertEqual(allowed, ["api.github.com"])
        XCTAssertTrue(denied.isEmpty)
    }

    func testHostExecutableFallback() throws {
        let parser = PolicyParser()
        try parser.parse(
            policyIdentifier: "test.rules",
            policyFileContents: """
            prefix_rule(pattern=["git", "status"], decision="allow")
            host_executable(name="git", paths=["/usr/bin/git"])
            """
        )
        let policy = parser.build()
        let matched = policy.matchesForCommandWithOptions(
            ["/usr/bin/git", "status"],
            heuristicsFallback: nil,
            options: MatchOptions(resolveHostExecutables: true)
        )
        XCTAssertFalse(matched.isEmpty)
        if case .prefixRuleMatch(_, let decision, let resolved, _) = matched[0] {
            XCTAssertEqual(decision, .allow)
            XCTAssertEqual(resolved?.asPath, "/usr/bin/git")
        } else {
            XCTFail("expected prefix match")
        }
    }

    func testAmendPrefixRule() throws {
        let dir = NSTemporaryDirectory() + "execpolicy-" + UUID().uuidString
        let path = (dir as NSString).appendingPathComponent("default.rules")
        defer { try? FileManager.default.removeItem(atPath: dir) }
        try blockingAppendAllowPrefixRule(policyPath: path, prefix: ["echo", "Hello, world!"])
        let contents = try String(contentsOfFile: path, encoding: .utf8)
        XCTAssertEqual(
            contents,
            "prefix_rule(pattern=[\"echo\", \"Hello, world!\"], decision=\"allow\")\n"
        )
    }
}
