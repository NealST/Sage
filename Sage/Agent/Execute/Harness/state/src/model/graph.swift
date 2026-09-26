//
//  graph.swift
//  CodexState
//
//  Port of codex-rs/state/src/model/graph.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//

import Foundation

/// Status attached to a directional thread-spawn edge.
public enum DirectionalThreadSpawnEdgeStatus: String, Codable, Equatable, Sendable {
    case open
    case closed

    public var asStr: String { rawValue }
}
