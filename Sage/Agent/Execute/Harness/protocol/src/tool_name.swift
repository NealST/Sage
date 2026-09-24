//
//  tool_name.swift
//  CodexProtocol
//
//  Port of codex-rs/protocol/src/tool_name.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  Identifies a callable tool, preserving the namespace split when the model
//  provides one. Display joins namespace and name with no separator, exactly
//  like upstream's `Display` impl.
//

import Foundation

/// `DEFAULT_FUNCTION_NAMESPACE` — namespace for top-level function/custom tools.
public let DEFAULT_FUNCTION_NAMESPACE = "functions"

public struct ToolName: Hashable, Sendable {
    public var name: String
    public var namespace: String?

    /// `ToolName::new`.
    public init(namespace: String?, name: String) {
        self.name = name
        self.namespace = namespace
    }

    /// `ToolName::plain`.
    public init(plain name: String) {
        self.name = name
        self.namespace = nil
    }

    /// `ToolName::namespaced`.
    public init(namespaced namespace: String, name: String) {
        self.name = name
        self.namespace = namespace
    }

    /// `ToolName::with_default_namespace`.
    public func withDefaultNamespace() -> ToolName {
        var copy = self
        if copy.namespace?.isEmpty ?? true {
            copy.namespace = DEFAULT_FUNCTION_NAMESPACE
        }
        return copy
    }

    /// `ToolName::is_default_namespace`.
    public func isDefaultNamespace() -> Bool {
        guard let namespace, !namespace.isEmpty else { return true }
        return namespace == DEFAULT_FUNCTION_NAMESPACE
    }
}

extension ToolName: CustomStringConvertible {
    public var description: String {
        guard let namespace, !isDefaultNamespace() else { return name }
        return "\(namespace)\(name)"
    }
}

extension ToolName: Comparable {
    /// Upstream `Ord`: namespaced tools sort by (namespace, name); plain tools
    /// sort by (name, nil) — nil sorts before any wrapped value.
    public static func < (lhs: ToolName, rhs: ToolName) -> Bool {
        let left = lhs.sortKey
        let right = rhs.sortKey
        if left.primary != right.primary { return left.primary < right.primary }
        switch (left.secondary, right.secondary) {
        case (nil, nil): return false
        case (nil, .some): return true
        case (.some, nil): return false
        case (.some(let a), .some(let b)): return a < b
        }
    }

    private var sortKey: (primary: String, secondary: String?) {
        if let namespace {
            return (namespace, name)
        }
        return (name, nil)
    }
}

extension ToolName: Codable {
    private enum CodingKeys: String, CodingKey {
        case name
        case namespace
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        namespace = try container.decodeIfPresent(String.self, forKey: .namespace)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        // serde serializes `None` as an explicit null.
        try container.encode(namespace, forKey: .namespace)
    }
}
