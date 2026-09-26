//
//  state_db_bridge.swift
//  CodexCore
//
//  Port of codex-rs/core/src/state_db_bridge.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Sage `Config` stays in the app module. Callers pass `RolloutConfig`.
//

import CodexRollout
import Foundation

public typealias StateDbHandle = CodexRollout.StateDbHandle

public func initStateDb(_ config: RolloutConfig) -> StateDbHandle? {
    CodexRollout.initStateDb(config)
}
