//
//  shared_instructions.swift
//  CodexCore
//
//  Port of codex-rs/core/src/thread_manager/shared_instructions.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  AGENTS.md / user-instruction merge waits for Phase 8.
//

import Foundation

public struct SharedInstructions: Equatable, Sendable {
    public var text: String

    public init(text: String = "") {
        self.text = text
    }
}
