//
//  rule.swift
//  CodexExecPolicy
//
//  Port of codex-rs/execpolicy/src/rule.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  Prefix matching, network-host normalization, and example validation.
//  `Rule` is a protocol (`dyn Rule` / `RuleRef = Arc<dyn Rule>`).
//

import CodexUtils
import Foundation

public enum PatternToken: Equatable, Sendable {
    case single(String)
    case alts([String])

    func matches(_ token: String) -> Bool {
        switch self {
        case .single(let expected):
            return expected == token
        case .alts(let alternatives):
            return alternatives.contains(token)
        }
    }

    public func alternatives() -> [String] {
        switch self {
        case .single(let expected):
            return [expected]
        case .alts(let alternatives):
            return alternatives
        }
    }
}

public struct PrefixPattern: Equatable, Sendable {
    public var first: String
    public var rest: [PatternToken]

    public init(first: String, rest: [PatternToken]) {
        self.first = first
        self.rest = rest
    }

    public func matchesPrefix(_ cmd: [String]) -> [String]? {
        let patternLength = rest.count + 1
        if cmd.count < patternLength || cmd[0] != first {
            return nil
        }
        for (patternToken, cmdToken) in zip(rest, cmd.dropFirst().prefix(rest.count)) {
            if !patternToken.matches(cmdToken) {
                return nil
            }
        }
        return Array(cmd.prefix(patternLength))
    }
}

public enum RuleMatch: Equatable, Sendable {
    case prefixRuleMatch(
        matchedPrefix: [String],
        decision: Decision,
        resolvedProgram: AbsolutePathBuf?,
        justification: String?
    )
    case heuristicsRuleMatch(command: [String], decision: Decision)

    public func decision() -> Decision {
        switch self {
        case .prefixRuleMatch(_, let decision, _, _):
            return decision
        case .heuristicsRuleMatch(_, let decision):
            return decision
        }
    }

    public func withResolvedProgram(_ resolvedProgram: AbsolutePathBuf) -> RuleMatch {
        switch self {
        case .prefixRuleMatch(let matchedPrefix, let decision, _, let justification):
            return .prefixRuleMatch(
                matchedPrefix: matchedPrefix,
                decision: decision,
                resolvedProgram: resolvedProgram,
                justification: justification
            )
        case .heuristicsRuleMatch:
            return self
        }
    }
}

extension RuleMatch: Codable {
    private enum VariantKey: String, CodingKey {
        case prefixRuleMatch
        case heuristicsRuleMatch
    }

    private enum PrefixKeys: String, CodingKey {
        case matchedPrefix
        case decision
        case resolvedProgram
        case justification
    }

    private enum HeuristicKeys: String, CodingKey {
        case command
        case decision
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: VariantKey.self)
        if container.contains(.prefixRuleMatch) {
            let nested = try container.nestedContainer(keyedBy: PrefixKeys.self, forKey: .prefixRuleMatch)
            self = .prefixRuleMatch(
                matchedPrefix: try nested.decode([String].self, forKey: .matchedPrefix),
                decision: try nested.decode(Decision.self, forKey: .decision),
                resolvedProgram: try nested.decodeIfPresent(AbsolutePathBuf.self, forKey: .resolvedProgram),
                justification: try nested.decodeIfPresent(String.self, forKey: .justification)
            )
        } else if container.contains(.heuristicsRuleMatch) {
            let nested = try container.nestedContainer(keyedBy: HeuristicKeys.self, forKey: .heuristicsRuleMatch)
            self = .heuristicsRuleMatch(
                command: try nested.decode([String].self, forKey: .command),
                decision: try nested.decode(Decision.self, forKey: .decision)
            )
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "unknown RuleMatch")
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: VariantKey.self)
        switch self {
        case .prefixRuleMatch(let matchedPrefix, let decision, let resolvedProgram, let justification):
            var nested = container.nestedContainer(keyedBy: PrefixKeys.self, forKey: .prefixRuleMatch)
            try nested.encode(matchedPrefix, forKey: .matchedPrefix)
            try nested.encode(decision, forKey: .decision)
            try nested.encodeIfPresent(resolvedProgram, forKey: .resolvedProgram)
            try nested.encodeIfPresent(justification, forKey: .justification)
        case .heuristicsRuleMatch(let command, let decision):
            var nested = container.nestedContainer(keyedBy: HeuristicKeys.self, forKey: .heuristicsRuleMatch)
            try nested.encode(command, forKey: .command)
            try nested.encode(decision, forKey: .decision)
        }
    }
}

public final class PrefixRule: ExecPolicyRule, @unchecked Sendable {
    public var pattern: PrefixPattern
    public var decision: Decision
    public var justification: String?

    public init(pattern: PrefixPattern, decision: Decision, justification: String? = nil) {
        self.pattern = pattern
        self.decision = decision
        self.justification = justification
    }

    public func program() -> String {
        pattern.first
    }

    public func matches(_ cmd: [String]) -> RuleMatch? {
        guard let matchedPrefix = pattern.matchesPrefix(cmd) else { return nil }
        return .prefixRuleMatch(
            matchedPrefix: matchedPrefix,
            decision: decision,
            resolvedProgram: nil,
            justification: justification
        )
    }
}

public enum NetworkRuleProtocol: Equatable, Sendable {
    case http
    case https
    case socks5Tcp
    case socks5Udp

    public static func parse(_ raw: String) throws -> NetworkRuleProtocol {
        switch raw {
        case "http": return .http
        case "https", "https_connect", "http-connect": return .https
        case "socks5_tcp": return .socks5Tcp
        case "socks5_udp": return .socks5Udp
        default:
            throw ExecPolicyError.invalidRule(
                "network_rule protocol must be one of http, https, socks5_tcp, socks5_udp (got \(raw))"
            )
        }
    }

    public func asPolicyString() -> String {
        switch self {
        case .http: return "http"
        case .https: return "https"
        case .socks5Tcp: return "socks5_tcp"
        case .socks5Udp: return "socks5_udp"
        }
    }
}

public struct NetworkRule: Equatable, Sendable {
    public var host: String
    public var protocol_: NetworkRuleProtocol
    public var decision: Decision
    public var justification: String?

    public init(
        host: String,
        protocol_: NetworkRuleProtocol,
        decision: Decision,
        justification: String? = nil
    ) {
        self.host = host
        self.protocol_ = protocol_
        self.decision = decision
        self.justification = justification
    }
}

public func normalizeNetworkRuleHost(_ raw: String) throws -> String {
    var host = raw.trimmingCharacters(in: .whitespaces)
    if host.isEmpty {
        throw ExecPolicyError.invalidRule("network_rule host cannot be empty")
    }
    if host.contains("://") || host.contains("/") || host.contains("?") || host.contains("#") {
        throw ExecPolicyError.invalidRule(
            "network_rule host must be a hostname or IP literal (without scheme or path)"
        )
    }

    if host.hasPrefix("[") {
        guard let close = host.firstIndex(of: "]") else {
            throw ExecPolicyError.invalidRule(
                "network_rule host has an invalid bracketed IPv6 literal"
            )
        }
        let rest = String(host[host.index(after: close)...])
        let portOK: Bool = {
            guard rest.hasPrefix(":") else { return rest.isEmpty }
            let port = String(rest.dropFirst())
            return !port.isEmpty && port.unicodeScalars.allSatisfy { CharacterSet.decimalDigits.contains($0) }
        }()
        if !rest.isEmpty && !portOK {
            throw ExecPolicyError.invalidRule(
                "network_rule host contains an unsupported suffix: \(raw)"
            )
        }
        host = String(host[host.index(after: host.startIndex)..<close])
    } else if host.filter({ $0 == ":" }).count == 1,
              let colon = host.lastIndex(of: ":") {
        let candidate = String(host[..<colon])
        let port = String(host[host.index(after: colon)...])
        if !candidate.isEmpty,
           !port.isEmpty,
           port.unicodeScalars.allSatisfy({ CharacterSet.decimalDigits.contains($0) }) {
            host = candidate
        }
    }

    let normalized = host.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        .trimmingCharacters(in: .whitespaces)
        .lowercased()
    if normalized.isEmpty {
        throw ExecPolicyError.invalidRule("network_rule host cannot be empty")
    }
    if normalized.contains("*") {
        throw ExecPolicyError.invalidRule(
            "network_rule host must be a specific host; wildcards are not allowed"
        )
    }
    if normalized.contains(where: { $0.isWhitespace }) {
        throw ExecPolicyError.invalidRule("network_rule host cannot contain whitespace")
    }
    return normalized
}

public protocol ExecPolicyRule: AnyObject, Sendable {
    func program() -> String
    func matches(_ cmd: [String]) -> RuleMatch?
}

func validateMatchExamples(
    policy: Policy,
    rules: [any ExecPolicyRule],
    matches: [[String]]
) throws {
    var unmatchedExamples: [String] = []
    let options = MatchOptions(resolveHostExecutables: true)
    for example in matches {
        if !policy.matchesForCommandWithOptions(example, heuristicsFallback: nil, options: options).isEmpty {
            continue
        }
        unmatchedExamples.append(shlexJoin(example) ?? "unable to render example")
    }
    if !unmatchedExamples.isEmpty {
        throw ExecPolicyError.exampleDidNotMatch(
            rules: rules.map { String(describing: $0) },
            examples: unmatchedExamples,
            location: nil
        )
    }
}

func validateNotMatchExamples(
    policy: Policy,
    rules _: [any ExecPolicyRule],
    notMatches: [[String]]
) throws {
    let options = MatchOptions(resolveHostExecutables: true)
    for example in notMatches {
        if let rule = policy.matchesForCommandWithOptions(example, heuristicsFallback: nil, options: options).first {
            throw ExecPolicyError.exampleDidMatch(
                rule: String(describing: rule),
                example: shlexJoin(example) ?? "unable to render example",
                location: nil
            )
        }
    }
}

func shlexJoin(_ tokens: [String]) -> String? {
    tokens.map(shlexQuote).joined(separator: " ")
}

func shlexQuote(_ token: String) -> String {
    if token.isEmpty { return "''" }
    if token.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "@%+=:,./-_")).contains($0) }) {
        return token
    }
    return "'" + token.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
}
