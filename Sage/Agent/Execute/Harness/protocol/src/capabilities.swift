//
//  capabilities.swift
//  CodexProtocol
//
//  Port of codex-rs/protocol/src/capabilities.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  User-selected capability roots. `schemars`/`ts_rs` derives are not ported.
//  `PathUri`/`LegacyAppPathString` come from CodexUtils (the protocol crate
//  depends on the utils crates upstream).
//

import CodexUtils
import Foundation

/// A user-selected root that can expose one or more runtime capabilities.
public struct SelectedCapabilityRoot: Codable, Equatable, Sendable {
    /// Stable identifier supplied by the capability selection platform.
    public var id: String
    /// Where the selected root can be resolved.
    public var location: CapabilityRootLocation

    public init(id: String, location: CapabilityRootLocation) {
        self.id = id
        self.location = location
    }

    private enum CodingKeys: String, CodingKey {
        case id, location
    }
}

/// Location used to resolve a selected capability root.
///
/// serde `tag = "type"` + `rename_all = "camelCase"`.
public enum CapabilityRootLocation: Codable, Equatable, Sendable {
    /// A path owned by an execution environment.
    case environment(environmentId: String, path: PathUri)

    private enum TypeKey: String, CodingKey { case type_ = "type" }
    private enum Keys: String, CodingKey {
        case environmentId
        case path
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: TypeKey.self)
        let type_ = try container.decode(String.self, forKey: .type_)
        switch type_ {
        case "environment":
            let keys = try decoder.container(keyedBy: Keys.self)
            self = .environment(
                environmentId: try keys.decode(String.self, forKey: .environmentId),
                path: try Self.decodePathUriFromAPIPath(keys: keys)
            )
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type_, in: container,
                debugDescription: "Unknown CapabilityRootLocation type: \(type_)")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: TypeKey.self)
        var keys = encoder.container(keyedBy: Keys.self)
        switch self {
        case .environment(let environmentId, let path):
            try container.encode("environment", forKey: .type_)
            try keys.encode(environmentId, forKey: .environmentId)
            // `PathUri` serializes as its URI string upstream.
            try keys.encode(path, forKey: .path)
        }
    }

    /// `deserialize_path_uri_from_api_path`: accept a legacy API path string,
    /// preferring a strict `PathUri` parse and falling back to the legacy
    /// native-path conversion.
    private static func decodePathUriFromAPIPath(
        keys: KeyedDecodingContainer<Keys>
    ) throws -> PathUri {
        let path = try keys.decode(LegacyAppPathString.self, forKey: .path)
        if let pathUri = try? PathUri.parse(path.asStr()) {
            return pathUri
        }
        do {
            return try PathUri(fromLegacy: path)
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: .path, in: keys,
                debugDescription: "invalid capability root path: \(error)")
        }
    }
}
