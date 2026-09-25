//
//  error.swift
//  CodexExecPolicy
//
//  Port of codex-rs/execpolicy/src/error.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Error messages match upstream `thiserror` text. `Starlark` carries a
//  string instead of the Rust `starlark::Error` (plan §10.1); span-derived
//  locations are filled by the subset parser when it has a source range.
//

public struct TextPosition: Equatable, Sendable {
    public var line: Int
    public var column: Int

    public init(line: Int, column: Int) {
        self.line = line
        self.column = column
    }
}

public struct TextRange: Equatable, Sendable {
    public var start: TextPosition
    public var end: TextPosition

    public init(start: TextPosition, end: TextPosition) {
        self.start = start
        self.end = end
    }
}

public struct ErrorLocation: Equatable, Sendable {
    public var path: String
    public var range: TextRange

    public init(path: String, range: TextRange) {
        self.path = path
        self.range = range
    }
}

public enum ExecPolicyError: Error, Equatable, CustomStringConvertible {
    case invalidDecision(String)
    case invalidPattern(String)
    case invalidExample(String)
    case invalidRule(String)
    case exampleDidNotMatch(rules: [String], examples: [String], location: ErrorLocation?)
    case exampleDidMatch(rule: String, example: String, location: ErrorLocation?)
    case starlark(String, location: ErrorLocation?)

    public var description: String {
        switch self {
        case .invalidDecision(let value):
            return "invalid decision: \(value)"
        case .invalidPattern(let value):
            return "invalid pattern element: \(value)"
        case .invalidExample(let value):
            return "invalid example: \(value)"
        case .invalidRule(let value):
            return "invalid rule: \(value)"
        case .exampleDidNotMatch(let rules, let examples, _):
            return "expected every example to match at least one rule. rules: \(rules); unmatched examples: \(examples)"
        case .exampleDidMatch(let rule, let example, _):
            return "expected example to not match rule `\(rule)`: \(example)"
        case .starlark(let message, _):
            return "starlark error: \(message)"
        }
    }

    public func withLocation(_ location: ErrorLocation) -> ExecPolicyError {
        switch self {
        case .exampleDidNotMatch(let rules, let examples, nil):
            return .exampleDidNotMatch(rules: rules, examples: examples, location: location)
        case .exampleDidMatch(let rule, let example, nil):
            return .exampleDidMatch(rule: rule, example: example, location: location)
        default:
            return self
        }
    }

    public var location: ErrorLocation? {
        switch self {
        case .exampleDidNotMatch(_, _, let location),
             .exampleDidMatch(_, _, let location),
             .starlark(_, let location):
            return location
        default:
            return nil
        }
    }
}
