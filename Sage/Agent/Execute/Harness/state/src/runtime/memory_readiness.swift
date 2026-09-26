//
//  memory_readiness.swift
//  CodexState
//
//  Port of codex-rs/state/src/runtime/memory_readiness.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Consolidation-progress SQL waits on the memories pool.
//

import Foundation

extension MemoryStore {
    /// Largest number of distinct source threads included in a successful consolidation.
    /// Kept across ordinary pruning, and cleared by an explicit memory reset.
    public func maxConsolidatedThreadCount() async throws -> UInt32 {
        throw StateRuntimeError.sqliteUnavailable("memories")
    }
}
