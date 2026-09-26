//
//  write_stdin.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/handlers/unified_exec/write_stdin.rs
//  (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Session write-stdin wait for Phase 5. The public handler is
//  WriteStdinHandler in unified_exec.swift.
//

struct WriteStdinSessionRequest: Equatable, Sendable {
    var sessionId: UInt64
    var chars: String
    var yieldTimeMs: UInt64
    var maxOutputTokens: Int?
}
