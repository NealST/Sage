//
//  mcp_skill_dependencies.swift
//  CodexCore
//
//  Port of codex-rs/core/src/mcp_skill_dependencies.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import Foundation

public struct McpSkillDependencies: Equatable, Sendable {
    public var requiredServers: [String]

    public init(requiredServers: [String] = []) {
        self.requiredServers = requiredServers
    }
}
