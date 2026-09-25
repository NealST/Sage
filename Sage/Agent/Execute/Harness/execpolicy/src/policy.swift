//
//  policy.swift
//  CodexExecPolicy
//
//  Port of codex-rs/execpolicy/src/policy.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  Prefix-rule matching, host-executable fallback, and Evaluation aggregation.
//  `MultiMap` is a dictionary of arrays that preserves insertion order per key.
//

import CodexUtils
import Foundation

public struct MatchOptions: Equatable, Sendable {
    public var resolveHostExecutables: Bool

    public init(resolveHostExecutables: Bool = false) {
        self.resolveHostExecutables = resolveHostExecutables
    }
}

public final class Policy: @unchecked Sendable {
    var rulesByProgram: [String: [any ExecPolicyRule]]
    var networkRules: [NetworkRule]
    var hostExecutablesByName: [String: [AbsolutePathBuf]]

    public init(
        rulesByProgram: [String: [any ExecPolicyRule]] = [:],
        networkRules: [NetworkRule] = [],
        hostExecutablesByName: [String: [AbsolutePathBuf]] = [:]
    ) {
        self.rulesByProgram = rulesByProgram
        self.networkRules = networkRules
        self.hostExecutablesByName = hostExecutablesByName
    }

    public static func fromParts(
        rulesByProgram: [String: [any ExecPolicyRule]],
        networkRules: [NetworkRule],
        hostExecutablesByName: [String: [AbsolutePathBuf]]
    ) -> Policy {
        Policy(
            rulesByProgram: rulesByProgram,
            networkRules: networkRules,
            hostExecutablesByName: hostExecutablesByName
        )
    }

    public static func empty() -> Policy {
        Policy()
    }

    public func rules() -> [String: [any ExecPolicyRule]] {
        rulesByProgram
    }

    public func networkRulesList() -> [NetworkRule] {
        networkRules
    }

    public func hostExecutables() -> [String: [AbsolutePathBuf]] {
        hostExecutablesByName
    }

    public func getAllowedPrefixes() -> [[String]] {
        var prefixes: [[String]] = []
        for (_, rules) in rulesByProgram {
            for rule in rules {
                guard let prefixRule = rule as? PrefixRule, prefixRule.decision == .allow else {
                    continue
                }
                var prefix: [String] = [prefixRule.pattern.first]
                prefix.append(contentsOf: prefixRule.pattern.rest.map(renderPatternToken))
                prefixes.append(prefix)
            }
        }
        prefixes.sort { $0.lexicographicallyPrecedes($1) }
        var deduped: [[String]] = []
        for prefix in prefixes where deduped.last != prefix {
            deduped.append(prefix)
        }
        return deduped
    }

    public func addPrefixRule(_ prefix: [String], decision: Decision) throws {
        guard let firstToken = prefix.first else {
            throw ExecPolicyError.invalidPattern("prefix cannot be empty")
        }
        let rest = prefix.dropFirst().map { PatternToken.single($0) }
        let rule = PrefixRule(
            pattern: PrefixPattern(first: firstToken, rest: rest),
            decision: decision,
            justification: nil
        )
        rulesByProgram[firstToken, default: []].append(rule)
    }

    public func addNetworkRule(
        host: String,
        protocol_: NetworkRuleProtocol,
        decision: Decision,
        justification: String? = nil
    ) throws {
        let host = try normalizeNetworkRuleHost(host)
        if let raw = justification, raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ExecPolicyError.invalidRule("justification cannot be empty")
        }
        networkRules.append(
            NetworkRule(host: host, protocol_: protocol_, decision: decision, justification: justification)
        )
    }

    public func setHostExecutablePaths(name: String, paths: [AbsolutePathBuf]) {
        hostExecutablesByName[name] = paths
    }

    public func mergeOverlay(_ overlay: Policy) -> Policy {
        var combined = rulesByProgram
        for (program, rules) in overlay.rulesByProgram {
            combined[program, default: []].append(contentsOf: rules)
        }
        var combinedNetwork = networkRules
        combinedNetwork.append(contentsOf: overlay.networkRules)
        var hostExecutables = hostExecutablesByName
        for (name, paths) in overlay.hostExecutablesByName {
            hostExecutables[name] = paths
        }
        return Policy.fromParts(
            rulesByProgram: combined,
            networkRules: combinedNetwork,
            hostExecutablesByName: hostExecutables
        )
    }

    public func compiledNetworkDomains() -> (allowed: [String], denied: [String]) {
        var allowed: [String] = []
        var denied: [String] = []
        for rule in networkRules {
            switch rule.decision {
            case .allow:
                denied.removeAll { $0 == rule.host }
                upsertDomain(&allowed, host: rule.host)
            case .forbidden:
                allowed.removeAll { $0 == rule.host }
                upsertDomain(&denied, host: rule.host)
            case .prompt:
                break
            }
        }
        return (allowed, denied)
    }

    public func check(_ cmd: [String], heuristicsFallback: @escaping ( [String] ) -> Decision) -> Evaluation {
        checkWithOptions(cmd, heuristicsFallback: heuristicsFallback, options: MatchOptions())
    }

    public func checkWithOptions(
        _ cmd: [String],
        heuristicsFallback: @escaping ( [String] ) -> Decision,
        options: MatchOptions
    ) -> Evaluation {
        let matched = matchesForCommandWithOptions(cmd, heuristicsFallback: heuristicsFallback, options: options)
        return Evaluation.fromMatches(matched)
    }

    public func checkMultiple(
        _ commands: [[String]],
        heuristicsFallback: @escaping ( [String] ) -> Decision
    ) -> Evaluation {
        checkMultipleWithOptions(commands, heuristicsFallback: heuristicsFallback, options: MatchOptions())
    }

    public func checkMultipleWithOptions(
        _ commands: [[String]],
        heuristicsFallback: @escaping ( [String] ) -> Decision,
        options: MatchOptions
    ) -> Evaluation {
        let matched = commands.flatMap {
            matchesForCommandWithOptions($0, heuristicsFallback: heuristicsFallback, options: options)
        }
        return Evaluation.fromMatches(matched)
    }

    public func matchesForCommand(
        _ cmd: [String],
        heuristicsFallback: (( [String] ) -> Decision)?
    ) -> [RuleMatch] {
        matchesForCommandWithOptions(cmd, heuristicsFallback: heuristicsFallback, options: MatchOptions())
    }

    public func matchesForCommandWithOptions(
        _ cmd: [String],
        heuristicsFallback: (( [String] ) -> Decision)?,
        options: MatchOptions
    ) -> [RuleMatch] {
        var matchedRules = matchExactRules(cmd)
        if matchedRules.isEmpty && options.resolveHostExecutables {
            matchedRules = matchHostExecutableRules(cmd)
        }
        if matchedRules.isEmpty, let heuristicsFallback {
            return [.heuristicsRuleMatch(command: cmd, decision: heuristicsFallback(cmd))]
        }
        return matchedRules
    }

    private func matchExactRules(_ cmd: [String]) -> [RuleMatch] {
        guard let first = cmd.first else { return [] }
        return (rulesByProgram[first] ?? []).compactMap { $0.matches(cmd) }
    }

    private func matchHostExecutableRules(_ cmd: [String]) -> [RuleMatch] {
        guard let first = cmd.first, first.hasPrefix("/") else { return [] }
        guard let program = try? AbsolutePathBuf.fromAbsolutePath(first) else { return [] }
        guard let basename = executablePathLookupKey(program.asPath) else { return [] }
        guard let rules = rulesByProgram[basename] else { return [] }
        if let paths = hostExecutablesByName[basename], !paths.contains(program) {
            return []
        }
        let basenameCommand = [basename] + Array(cmd.dropFirst())
        return rules.compactMap { $0.matches(basenameCommand)?.withResolvedProgram(program) }
    }
}

public final class RequirementsExecPolicy: @unchecked Sendable {
    public let policy: Policy

    public init(_ policy: Policy) {
        self.policy = policy
    }

    public func fingerprint() -> [String] {
        var entries: [String] = []
        for (program, rules) in policy.rules() {
            for rule in rules {
                entries.append("\(program):\(String(describing: rule))")
            }
        }
        return entries.sorted()
    }
}

extension RequirementsExecPolicy: Equatable {
    public static func == (lhs: RequirementsExecPolicy, rhs: RequirementsExecPolicy) -> Bool {
        lhs.fingerprint() == rhs.fingerprint()
    }
}

public struct Evaluation: Equatable, Sendable {
    public var decision: Decision
    public var matchedRules: [RuleMatch]

    public init(decision: Decision, matchedRules: [RuleMatch]) {
        self.decision = decision
        self.matchedRules = matchedRules
    }

    public func isMatch() -> Bool {
        matchedRules.contains { match in
            if case .heuristicsRuleMatch = match { return false }
            return true
        }
    }

    static func fromMatches(_ matchedRules: [RuleMatch]) -> Evaluation {
        precondition(!matchedRules.isEmpty, "invariant failed: matched_rules must be non-empty")
        let decision = matchedRules.map { $0.decision() }.max()!
        return Evaluation(decision: decision, matchedRules: matchedRules)
    }
}

extension Evaluation: Codable {
    enum CodingKeys: String, CodingKey {
        case decision
        case matchedRules
    }
}

private func upsertDomain(_ entries: inout [String], host: String) {
    entries.removeAll { $0 == host }
    entries.append(host)
}

func renderPatternToken(_ token: PatternToken) -> String {
    switch token {
    case .single(let value):
        return value
    case .alts(let alternatives):
        return "[\(alternatives.joined(separator: "|"))]"
    }
}
