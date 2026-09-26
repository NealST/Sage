//
//  exec_command.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/handlers/unified_exec/exec_command.rs
//  (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Session exec session + orchestrator wait for Phase 5. Types and
//  argument parsing live next to unified_exec.swift.
//

import CodexCore

struct ExecCommandSessionRequest: Equatable, Sendable {
    var command: [String]
    var workdir: String?
    var yieldTimeMs: UInt64
    var maxOutputTokens: Int?
    var tty: Bool
}

func defaultExecYieldTimeMs() -> UInt64 { 10_000 }
func defaultWriteStdinYieldTimeMs() -> UInt64 { 250 }
func defaultTty() -> Bool { false }
