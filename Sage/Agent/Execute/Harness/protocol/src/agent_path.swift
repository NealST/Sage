//
//  agent_path.swift
//  CodexProtocol
//
//  Port of codex-rs/protocol/src/agent_path.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  Validated hierarchical agent path for multi-agent trees. The root path is
//  `/root`; child paths are joined with `/`. Morpheus is a special standalone
//  path at `/morpheus`.
//

import Foundation

// MARK: - AgentPath

public struct AgentPath: Hashable, Comparable, Sendable, CustomStringConvertible {
    private let value: String

    public static let rootString = "/root"
    public static let morpheusString = "/morpheus"
    private static let rootSegment = "root"

    public static func root() -> AgentPath {
        AgentPath(unchecked: rootString)
    }

    public static func morpheus() -> AgentPath {
        AgentPath(unchecked: morpheusString)
    }

    private init(unchecked value: String) { self.value = value }

    public init(string: String) throws {
        try AgentPath.validateAbsolutePath(string)
        self.value = string
    }

    public var asStr: String { value }
    public var description: String { value }

    public var isRoot: Bool { value == AgentPath.rootString }

    public var name: String {
        if isRoot { return AgentPath.rootSegment }
        if let last = value.split(separator: "/").last, !last.isEmpty {
            return String(last)
        }
        return AgentPath.rootSegment
    }

    public func join(_ agentName: String) throws -> AgentPath {
        try AgentPath.validateAgentName(agentName)
        return try AgentPath(string: "\(value)/\(agentName)")
    }

    public func resolve(_ reference: String) throws -> AgentPath {
        guard !reference.isEmpty else {
            throw AgentPathError.emptyPath
        }
        if reference == AgentPath.rootString {
            return .root()
        }
        if reference.hasPrefix("/") {
            return try AgentPath(string: reference)
        }
        try AgentPath.validateRelativeReference(reference)
        return try AgentPath(string: "\(value)/\(reference)")
    }

    public static func < (lhs: AgentPath, rhs: AgentPath) -> Bool {
        lhs.value < rhs.value
    }

    // MARK: - Validation

    private static func validateAgentName(_ name: String) throws {
        if name.isEmpty {
            throw AgentPathError.emptyName
        }
        if name == rootSegment {
            throw AgentPathError.reservedName(name)
        }
        if name == "." || name == ".." {
            throw AgentPathError.reservedName(name)
        }
        if name.contains("/") {
            throw AgentPathError.slashInName
        }
        let valid = name.allSatisfy { ch in
            (ch.isASCII && ch.isLowercase) || ch.isNumber || ch == "_"
        }
        if !valid {
            throw AgentPathError.invalidCharacters
        }
    }

    private static func validateAbsolutePath(_ path: String) throws {
        if path == morpheusString { return }
        guard let stripped = path.stripPrefix("/") else {
            throw AgentPathError.mustStartWithRoot
        }
        var segments = stripped.split(separator: "/", omittingEmptySubsequences: false).makeIterator()
        guard let first = segments.next(), first == rootSegment else {
            throw AgentPathError.mustStartWithRoot
        }
        if stripped.hasSuffix("/") {
            throw AgentPathError.trailingSlash
        }
        while let segment = segments.next() {
            try validateAgentName(String(segment))
        }
    }

    private static func validateRelativeReference(_ reference: String) throws {
        if reference.hasSuffix("/") {
            throw AgentPathError.trailingSlashRelative
        }
        for segment in reference.split(separator: "/") {
            try validateAgentName(String(segment))
        }
    }
}

private extension String {
    func stripPrefix(_ prefix: String) -> String? {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : nil
    }
}

// MARK: - AgentPath + Codable

extension AgentPath: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        do {
            try self.init(string: raw)
        } catch {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "\(error)")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

// MARK: - AgentPathError

public enum AgentPathError: Error, Equatable, CustomStringConvertible {
    case emptyPath
    case emptyName
    case reservedName(String)
    case slashInName
    case invalidCharacters
    case mustStartWithRoot
    case trailingSlash
    case trailingSlashRelative

    public var description: String {
        switch self {
        case .emptyPath: "agent path must not be empty"
        case .emptyName: "agent_name must not be empty"
        case .reservedName(let n): "agent_name `\(n)` is reserved"
        case .slashInName: "agent_name must not contain `/`"
        case .invalidCharacters: "agent_name must use only lowercase letters, digits, and underscores"
        case .mustStartWithRoot: "absolute agent paths must start with `/root` or be `/morpheus`"
        case .trailingSlash: "absolute agent path must not end with `/`"
        case .trailingSlashRelative: "relative agent path must not end with `/`"
        }
    }
}
