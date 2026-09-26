//
//  launch.swift
//  ToolsRuntimes
//
//  Port of codex-rs/core/src/tools/runtimes/unified_exec/launch.rs
//  (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import Foundation

public struct UnifiedExecLaunch: Equatable, Sendable {
    public var command: [String]
    public var cwd: URL
    public var env: [String: String]

    public init(command: [String], cwd: URL, env: [String: String]) {
        self.command = command
        self.cwd = cwd
        self.env = env
    }
}
