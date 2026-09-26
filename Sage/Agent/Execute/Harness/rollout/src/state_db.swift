//
//  state_db.swift
//  CodexRollout
//
//  Port of codex-rs/rollout/src/state_db.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  sqlx handle maps to an opaque token until the GRDB runtime is ported.
//

import Foundation

public struct StateDbHandle: Sendable {
    public init() {}
}

public func initStateDb(_ config: RolloutConfig) -> StateDbHandle? {
    _ = config
    return nil
}
