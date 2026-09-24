//
//  response_item_id.swift
//  CodexProtocol
//
//  Port of codex-rs/protocol/src/response_item_id.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  A Responses API item ID. New IDs require an explicit prefix (UUIDv7
//  suffix); deserialization remains permissive so legacy rollouts still read.
//

import Foundation

public struct ResponseItemId: Hashable, Comparable, Sendable {
    private let value: String

    /// `ResponseItemId::new` — `<prefix>_<uuidv7>`.
    public init(new prefix: String) {
        self.init(withSuffix: prefix, suffix: UUIDv7.now().uuidString.lowercased())
    }

    /// `ResponseItemId::with_suffix`.
    public init(withSuffix prefix: String, suffix: String) {
        value = "\(prefix)_\(suffix)"
    }

    /// `ResponseItemId::from_server` — accept server IDs verbatim.
    public static func fromServer(_ value: String) -> ResponseItemId {
        ResponseItemId(value: value)
    }

    private init(value: String) {
        self.value = value
    }

    /// `as_str`.
    public var asStr: String {
        value
    }

    /// `is_prefixed` — non-empty prefix and suffix around the first `_`.
    public var isPrefixed: Bool {
        guard let underscore = value.firstIndex(of: "_") else { return false }
        let prefix = value[..<underscore]
        let suffix = value[value.index(after: underscore)...]
        return !prefix.isEmpty && !suffix.isEmpty
    }

    public static func < (lhs: ResponseItemId, rhs: ResponseItemId) -> Bool {
        lhs.value < rhs.value
    }
}

extension ResponseItemId: CustomStringConvertible {
    public var description: String {
        value
    }
}

extension ResponseItemId: Codable {
    // serde `transparent`: wire format is the bare string.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        value = try container.decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

extension ResponseItemId {
    /// `From<ResponseItemId> for String`.
    public var string: String {
        value
    }
}
