//
//  parse_command.swift
//  CodexProtocol
//
//  Port of codex-rs/protocol/src/parse_command.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  `PathBuf` maps to `String` on the wire (plan §5.4); the path semantics
//  stay with the producer. `schemars`/`ts_rs` derives carry no runtime
//  semantics and are not ported.
//

import Foundation

/// serde `tag = "type"`, `rename_all = "snake_case"`.
public enum ParsedCommand: Equatable, Sendable {
    case read(cmd: String, name: String, path: String)
    case listFiles(cmd: String, path: String?)
    case search(cmd: String, query: String?, path: String?)
    case unknown(cmd: String)
}

extension ParsedCommand: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case cmd
        case name
        case path
        case query
    }

    private enum Variant: String {
        case read
        case listFiles = "list_files"
        case search
        case unknown
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // serde treats `Option` fields as implicitly optional (missing → None).
        switch try container.decode(String.self, forKey: .type) {
        case Variant.read.rawValue:
            self = .read(
                cmd: try container.decode(String.self, forKey: .cmd),
                name: try container.decode(String.self, forKey: .name),
                path: try container.decode(String.self, forKey: .path)
            )
        case Variant.listFiles.rawValue:
            self = .listFiles(
                cmd: try container.decode(String.self, forKey: .cmd),
                path: try container.decodeIfPresent(String.self, forKey: .path)
            )
        case Variant.search.rawValue:
            self = .search(
                cmd: try container.decode(String.self, forKey: .cmd),
                query: try container.decodeIfPresent(String.self, forKey: .query),
                path: try container.decodeIfPresent(String.self, forKey: .path)
            )
        case Variant.unknown.rawValue:
            self = .unknown(cmd: try container.decode(String.self, forKey: .cmd))
        default:
            throw DecodingError.typeMismatch(
                ParsedCommand.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "unknown variant, expected `read`, `list_files`, `search` or `unknown`"
                )
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .read(let cmd, let name, let path):
            try container.encode(Variant.read.rawValue, forKey: .type)
            try container.encode(cmd, forKey: .cmd)
            try container.encode(name, forKey: .name)
            try container.encode(path, forKey: .path)
        case .listFiles(let cmd, let path):
            try container.encode(Variant.listFiles.rawValue, forKey: .type)
            try container.encode(cmd, forKey: .cmd)
            // No skip_serializing_if upstream: None encodes as explicit null.
            try container.encode(path, forKey: .path)
        case .search(let cmd, let query, let path):
            try container.encode(Variant.search.rawValue, forKey: .type)
            try container.encode(cmd, forKey: .cmd)
            try container.encode(query, forKey: .query)
            try container.encode(path, forKey: .path)
        case .unknown(let cmd):
            try container.encode(Variant.unknown.rawValue, forKey: .type)
            try container.encode(cmd, forKey: .cmd)
        }
    }
}
