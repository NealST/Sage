//
//  configuration_update.swift
//  CodexProtocol
//
//  Port of codex-rs/protocol/src/models/configuration_update.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//

import Foundation

public struct ConfigurationReasoning: Codable, Equatable, Sendable {
    public var effort: ReasoningEffort

    public init(effort: ReasoningEffort) { self.effort = effort }
}
