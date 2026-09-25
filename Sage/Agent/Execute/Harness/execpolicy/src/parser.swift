//
//  parser.swift
//  CodexExecPolicy
//
//  Port of codex-rs/execpolicy/src/parser.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Upstream evaluates policy files with the Rust `starlark` crate
//  (`prefix_rule` / `network_rule` / `host_executable` builtins). Swift has
//  no equivalent (plan §10.1). This parser accepts that prefix-rule subset:
//  comments, the three builtins, keyword arguments, nested string/list
//  literals, and `match` / `not_match` example validation. It rejects
//  f-strings, arithmetic, and other Starlark that is not in the documented
//  execpolicy language.
//

import CodexUtils
import Foundation

public final class PolicyParser {
    private var builder = PolicyBuilder()

    public init() {}

    /// Parses a policy, tagging parser errors with `policyIdentifier`.
    public func parse(policyIdentifier: String, policyFileContents: String) throws {
        let pendingCount = builder.pendingExampleValidations.count
        do {
            try parseSubset(policyIdentifier: policyIdentifier, source: policyFileContents)
        } catch let error as ExecPolicyError {
            throw error
        } catch {
            throw ExecPolicyError.starlark(String(describing: error), location: nil)
        }
        try builder.validatePendingExamples(from: pendingCount)
    }

    public func build() -> Policy {
        builder.build()
    }

    private func parseSubset(policyIdentifier: String, source: String) throws {
        let scanner = StarlarkSubsetScanner(source: source, path: policyIdentifier)
        while true {
            scanner.skipTrivia()
            if scanner.isAtEnd { break }
            let name = try scanner.identifier()
            try scanner.expect("(")
            switch name {
            case "prefix_rule":
                try parsePrefixRule(scanner)
            case "network_rule":
                try parseNetworkRule(scanner)
            case "host_executable":
                try parseHostExecutable(scanner)
            default:
                throw ExecPolicyError.starlark(
                    "unsupported builtin `\(name)` (prefix-rule subset only)",
                    location: scanner.location()
                )
            }
            try scanner.expect(")")
        }
    }

    private func parsePrefixRule(_ scanner: StarlarkSubsetScanner) throws {
        var patternValue: StarlarkValue?
        var decisionRaw: String?
        var matchValue: StarlarkValue?
        var notMatchValue: StarlarkValue?
        var justification: String?
        try scanner.keywordArgs { key, value in
            switch key {
            case "pattern": patternValue = value
            case "decision": decisionRaw = try value.string("decision")
            case "match": matchValue = value
            case "not_match": notMatchValue = value
            case "justification": justification = try value.string("justification")
            default:
                throw ExecPolicyError.invalidRule("unknown prefix_rule argument `\(key)`")
            }
        }
        let decision = try decisionRaw.map { try Decision.parse($0) } ?? .allow
        if let justification, justification.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ExecPolicyError.invalidRule("justification cannot be empty")
        }
        guard let patternValue else {
            throw ExecPolicyError.invalidPattern("pattern cannot be empty")
        }
        let patternTokens = try parsePattern(patternValue)
        guard let firstToken = patternTokens.first else {
            throw ExecPolicyError.invalidPattern("pattern cannot be empty")
        }
        let rest = Array(patternTokens.dropFirst())
        let matches = try matchValue.map { try parseExamples($0) } ?? []
        let notMatches = try notMatchValue.map { try parseExamples($0) } ?? []
        let location = scanner.location()

        let rules: [PrefixRule] = firstToken.alternatives().map { head in
            PrefixRule(
                pattern: PrefixPattern(first: head, rest: rest),
                decision: decision,
                justification: justification
            )
        }
        builder.addPendingExampleValidation(
            rules: rules,
            matches: matches,
            notMatches: notMatches,
            location: location
        )
        rules.forEach { builder.addRule($0) }
    }

    private func parseNetworkRule(_ scanner: StarlarkSubsetScanner) throws {
        var host: String?
        var protocolRaw: String?
        var decisionRaw: String?
        var justification: String?
        try scanner.keywordArgs { key, value in
            switch key {
            case "host": host = try value.string("host")
            case "protocol": protocolRaw = try value.string("protocol")
            case "decision": decisionRaw = try value.string("decision")
            case "justification": justification = try value.string("justification")
            default:
                throw ExecPolicyError.invalidRule("unknown network_rule argument `\(key)`")
            }
        }
        guard let host, let protocolRaw, let decisionRaw else {
            throw ExecPolicyError.invalidRule("network_rule requires host, protocol, and decision")
        }
        let protocol_ = try NetworkRuleProtocol.parse(protocolRaw)
        let decision = try parseNetworkRuleDecision(decisionRaw)
        if let justification, justification.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ExecPolicyError.invalidRule("justification cannot be empty")
        }
        builder.addNetworkRule(
            NetworkRule(
                host: try normalizeNetworkRuleHost(host),
                protocol_: protocol_,
                decision: decision,
                justification: justification
            )
        )
    }

    private func parseHostExecutable(_ scanner: StarlarkSubsetScanner) throws {
        var name: String?
        var pathsValue: StarlarkValue?
        try scanner.keywordArgs { key, value in
            switch key {
            case "name": name = try value.string("name")
            case "paths": pathsValue = value
            default:
                throw ExecPolicyError.invalidRule("unknown host_executable argument `\(key)`")
            }
        }
        guard let name else {
            throw ExecPolicyError.invalidRule("host_executable name cannot be empty")
        }
        try validateHostExecutableName(name)
        guard let pathsValue else {
            throw ExecPolicyError.invalidRule("host_executable paths must be a list")
        }
        let items = try pathsValue.list("paths")
        var parsedPaths: [AbsolutePathBuf] = []
        for item in items {
            let raw = try item.string("host_executable path")
            let path = try parseLiteralAbsolutePath(raw)
            guard let pathName = executablePathLookupKey(path.asPath) else {
                throw ExecPolicyError.invalidRule(
                    "host_executable path `\(raw)` must have basename `\(name)`"
                )
            }
            if pathName != executableLookupKey(name) {
                throw ExecPolicyError.invalidRule(
                    "host_executable path `\(raw)` must have basename `\(name)`"
                )
            }
            if !parsedPaths.contains(path) {
                parsedPaths.append(path)
            }
        }
        builder.addHostExecutable(executableLookupKey(name), paths: parsedPaths)
    }
}

private struct PolicyBuilder {
    var rulesByProgram: [String: [any ExecPolicyRule]] = [:]
    var networkRules: [NetworkRule] = []
    var hostExecutablesByName: [String: [AbsolutePathBuf]] = [:]
    var pendingExampleValidations: [PendingExampleValidation] = []

    mutating func addRule(_ rule: any ExecPolicyRule) {
        rulesByProgram[rule.program(), default: []].append(rule)
    }

    mutating func addNetworkRule(_ rule: NetworkRule) {
        networkRules.append(rule)
    }

    mutating func addHostExecutable(_ name: String, paths: [AbsolutePathBuf]) {
        hostExecutablesByName[name] = paths
    }

    mutating func addPendingExampleValidation(
        rules: [any ExecPolicyRule],
        matches: [[String]],
        notMatches: [[String]],
        location: ErrorLocation?
    ) {
        pendingExampleValidations.append(
            PendingExampleValidation(
                rules: rules,
                matches: matches,
                notMatches: notMatches,
                location: location
            )
        )
    }

    func validatePendingExamples(from start: Int) throws {
        for validation in pendingExampleValidations[start...] {
            var rulesByProgram: [String: [any ExecPolicyRule]] = [:]
            for rule in validation.rules {
                rulesByProgram[rule.program(), default: []].append(rule)
            }
            let policy = Policy.fromParts(
                rulesByProgram: rulesByProgram,
                networkRules: [],
                hostExecutablesByName: hostExecutablesByName
            )
            do {
                try validateNotMatchExamples(
                    policy: policy,
                    rules: validation.rules,
                    notMatches: validation.notMatches
                )
                try validateMatchExamples(
                    policy: policy,
                    rules: validation.rules,
                    matches: validation.matches
                )
            } catch let error as ExecPolicyError {
                throw attachValidationLocation(error, location: validation.location)
            }
        }
    }

    func build() -> Policy {
        Policy.fromParts(
            rulesByProgram: rulesByProgram,
            networkRules: networkRules,
            hostExecutablesByName: hostExecutablesByName
        )
    }
}

private struct PendingExampleValidation {
    var rules: [any ExecPolicyRule]
    var matches: [[String]]
    var notMatches: [[String]]
    var location: ErrorLocation?
}

private enum StarlarkValue {
    case string(String)
    case list([StarlarkValue])

    func string(_ label: String) throws -> String {
        if case .string(let value) = self { return value }
        throw ExecPolicyError.invalidPattern("\(label) must be a string")
    }

    func list(_ label: String) throws -> [StarlarkValue] {
        if case .list(let value) = self { return value }
        throw ExecPolicyError.invalidPattern("\(label) must be a list")
    }
}

private func parsePattern(_ value: StarlarkValue) throws -> [PatternToken] {
    let tokens = try value.list("pattern").map(parsePatternToken)
    if tokens.isEmpty {
        throw ExecPolicyError.invalidPattern("pattern cannot be empty")
    }
    return tokens
}

private func parsePatternToken(_ value: StarlarkValue) throws -> PatternToken {
    switch value {
    case .string(let s):
        return .single(s)
    case .list(let items):
        let tokens = try items.map { try $0.string("pattern alternative") }
        switch tokens.count {
        case 0:
            throw ExecPolicyError.invalidPattern("pattern alternatives cannot be empty")
        case 1:
            return .single(tokens[0])
        default:
            return .alts(tokens)
        }
    }
}

private func parseExamples(_ value: StarlarkValue) throws -> [[String]] {
    try value.list("examples").map(parseExample)
}

private func parseExample(_ value: StarlarkValue) throws -> [String] {
    switch value {
    case .string(let raw):
        return try parseStringExample(raw)
    case .list(let items):
        let tokens = try items.map { try $0.string("example token") }
        if tokens.isEmpty {
            throw ExecPolicyError.invalidExample("example cannot be an empty list")
        }
        return tokens
    }
}

private func parseStringExample(_ raw: String) throws -> [String] {
    guard let tokens = posixShlexSplit(raw) else {
        throw ExecPolicyError.invalidExample("example string has invalid shell syntax")
    }
    if tokens.isEmpty {
        throw ExecPolicyError.invalidExample("example cannot be an empty string")
    }
    return tokens
}

private func parseLiteralAbsolutePath(_ raw: String) throws -> AbsolutePathBuf {
    guard raw.hasPrefix("/") else {
        throw ExecPolicyError.invalidRule("host_executable paths must be absolute (got \(raw))")
    }
    do {
        return try AbsolutePathBuf.fromAbsolutePath(raw)
    } catch {
        throw ExecPolicyError.invalidRule("invalid absolute path `\(raw)`: \(error)")
    }
}

private func validateHostExecutableName(_ name: String) throws {
    if name.isEmpty {
        throw ExecPolicyError.invalidRule("host_executable name cannot be empty")
    }
    if name.contains("/") || (name as NSString).lastPathComponent != name {
        throw ExecPolicyError.invalidRule(
            "host_executable name must be a bare executable name (got \(name))"
        )
    }
}

private func parseNetworkRuleDecision(_ raw: String) throws -> Decision {
    if raw == "deny" { return .forbidden }
    return try Decision.parse(raw)
}

private func attachValidationLocation(_ error: ExecPolicyError, location: ErrorLocation?) -> ExecPolicyError {
    if let location { return error.withLocation(location) }
    return error
}

private final class StarlarkSubsetScanner {
    let source: String
    let path: String
    private(set) var index: String.Index

    init(source: String, path: String) {
        self.source = source
        self.path = path
        self.index = source.startIndex
    }

    var isAtEnd: Bool { index >= source.endIndex }

    func location() -> ErrorLocation {
        var line = 1
        var column = 1
        var i = source.startIndex
        while i < index {
            if source[i] == "\n" {
                line += 1
                column = 1
            } else {
                column += 1
            }
            i = source.index(after: i)
        }
        let position = TextPosition(line: line, column: column)
        return ErrorLocation(path: path, range: TextRange(start: position, end: position))
    }

    func skipTrivia() {
        while !isAtEnd {
            let ch = source[index]
            if ch.isWhitespace {
                index = source.index(after: index)
                continue
            }
            if ch == "#" {
                while !isAtEnd && source[index] != "\n" {
                    index = source.index(after: index)
                }
                continue
            }
            break
        }
    }

    func identifier() throws -> String {
        skipTrivia()
        guard !isAtEnd, source[index].isLetter || source[index] == "_" else {
            throw ExecPolicyError.starlark("expected identifier", location: location())
        }
        let start = index
        index = source.index(after: index)
        while !isAtEnd, source[index].isLetter || source[index].isNumber || source[index] == "_" {
            index = source.index(after: index)
        }
        return String(source[start..<index])
    }

    func expect(_ token: String) throws {
        skipTrivia()
        guard source[index...].hasPrefix(token) else {
            throw ExecPolicyError.starlark("expected `\(token)`", location: location())
        }
        index = source.index(index, offsetBy: token.count)
    }

    func peek() -> Character? {
        skipTrivia()
        return isAtEnd ? nil : source[index]
    }

    func keywordArgs(_ body: (String, StarlarkValue) throws -> Void) throws {
        skipTrivia()
        if peek() == ")" { return }
        while true {
            let key = try identifier()
            try expect("=")
            let value = try parseValue()
            try body(key, value)
            skipTrivia()
            if peek() == "," {
                index = source.index(after: index)
                skipTrivia()
                if peek() == ")" { break }
                continue
            }
            break
        }
    }

    func parseValue() throws -> StarlarkValue {
        skipTrivia()
        guard let ch = peek() else {
            throw ExecPolicyError.starlark("expected value", location: location())
        }
        if ch == "\"" || ch == "'" {
            return .string(try parseString())
        }
        if ch == "[" {
            return .list(try parseList())
        }
        throw ExecPolicyError.starlark("unsupported Starlark value", location: location())
    }

    private func parseString() throws -> String {
        skipTrivia()
        let quote = source[index]
        index = source.index(after: index)
        var out = ""
        while !isAtEnd {
            let ch = source[index]
            index = source.index(after: index)
            if ch == quote { return out }
            if ch == "\\" {
                guard !isAtEnd else {
                    throw ExecPolicyError.starlark("unterminated string", location: location())
                }
                let escaped = source[index]
                index = source.index(after: index)
                switch escaped {
                case "n": out.append("\n")
                case "t": out.append("\t")
                case "r": out.append("\r")
                case "\\": out.append("\\")
                case "\"": out.append("\"")
                case "'": out.append("'")
                default: out.append(escaped)
                }
            } else {
                out.append(ch)
            }
        }
        throw ExecPolicyError.starlark("unterminated string", location: location())
    }

    private func parseList() throws -> [StarlarkValue] {
        try expect("[")
        var items: [StarlarkValue] = []
        skipTrivia()
        if peek() == "]" {
            index = source.index(after: index)
            return items
        }
        while true {
            items.append(try parseValue())
            skipTrivia()
            if peek() == "," {
                index = source.index(after: index)
                skipTrivia()
                if peek() == "]" {
                    index = source.index(after: index)
                    break
                }
                continue
            }
            try expect("]")
            break
        }
        return items
    }
}

func posixShlexSplit(_ input: String) -> [String]? {
    var tokens: [String] = []
    var current = ""
    var inSingle = false
    var inDouble = false
    var escaped = false
    var sawToken = false

    for ch in input {
        if escaped {
            current.append(ch)
            escaped = false
            sawToken = true
            continue
        }
        if ch == "\\" && !inSingle {
            escaped = true
            sawToken = true
            continue
        }
        if ch == "'" && !inDouble {
            inSingle.toggle()
            sawToken = true
            continue
        }
        if ch == "\"" && !inSingle {
            inDouble.toggle()
            sawToken = true
            continue
        }
        if ch.isWhitespace && !inSingle && !inDouble {
            if sawToken {
                tokens.append(current)
                current = ""
                sawToken = false
            }
            continue
        }
        current.append(ch)
        sawToken = true
    }
    if inSingle || inDouble || escaped { return nil }
    if sawToken { tokens.append(current) }
    return tokens
}
