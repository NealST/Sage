//
//  execpolicycheck.swift
//  CodexExecPolicy
//
//  Port of codex-rs/execpolicy/src/execpolicycheck.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  clap CLI types are a Swift struct. `run()` still loads policies and
//  prints JSON; Sage callers use `loadPolicies` / `formatMatchesJSON`
//  instead of a standalone binary.
//

import Foundation

public struct ExecPolicyCheckCommand: Equatable, Sendable {
    public var rules: [String]
    public var pretty: Bool
    public var resolveHostExecutables: Bool
    public var command: [String]

    public init(
        rules: [String],
        pretty: Bool = false,
        resolveHostExecutables: Bool = false,
        command: [String]
    ) {
        self.rules = rules
        self.pretty = pretty
        self.resolveHostExecutables = resolveHostExecutables
        self.command = command
    }

    public func run() throws -> String {
        let policy = try loadPolicies(rules)
        let matched = policy.matchesForCommandWithOptions(
            command,
            heuristicsFallback: nil,
            options: MatchOptions(resolveHostExecutables: resolveHostExecutables)
        )
        return try formatMatchesJSON(matched, pretty: pretty)
    }
}

public func formatMatchesJSON(_ matchedRules: [RuleMatch], pretty: Bool) throws -> String {
    let output = ExecPolicyCheckOutput(
        matchedRules: matchedRules,
        decision: matchedRules.map { $0.decision() }.max()
    )
    let encoder = JSONEncoder()
    if pretty { encoder.outputFormatting = [.prettyPrinted] }
    let data = try encoder.encode(output)
    return String(data: data, encoding: .utf8) ?? "{}"
}

public func loadPolicies(_ policyPaths: [String]) throws -> Policy {
    let parser = PolicyParser()
    for policyPath in policyPaths {
        let contents = try String(contentsOfFile: policyPath, encoding: .utf8)
        try parser.parse(policyIdentifier: policyPath, policyFileContents: contents)
    }
    return parser.build()
}

private struct ExecPolicyCheckOutput: Encodable {
    var matchedRules: [RuleMatch]
    var decision: Decision?

    enum CodingKeys: String, CodingKey {
        case matchedRules
        case decision
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(matchedRules, forKey: .matchedRules)
        try container.encodeIfPresent(decision, forKey: .decision)
    }
}
