//
//  memory_version.swift
//  CodexProtocol
//
//  Port of codex-rs/protocol/src/memory_version.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  Selects a coherent memory pipeline and its generated-artifact namespace.
//

import Foundation

/// `MemoryVersion` — serde `rename_all = "lowercase"`, default `v1`.
public enum MemoryVersion: String, Codable, Sendable {
    case v1
    case v2

    /// Sibling roots keep v1 cleanup and rollback independent of v2 artifacts.
    public var directoryName: String {
        switch self {
        case .v1: return "memories"
        case .v2: return "memories_v2"
        }
    }
}
