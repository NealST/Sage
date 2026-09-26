//
//  process_state.swift
//  Sage
//
//  Port of codex-rs/core/src/unified_exec/process_state.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//

struct ProcessState: Equatable, Sendable {
    var hasExited = false
    var exitCode: Int32?
    var failureMessage: String?
    var sandboxDenied = false

    func exited(_ exitCode: Int32?) -> ProcessState {
        var copy = self
        copy.hasExited = true
        copy.exitCode = exitCode
        return copy
    }

    func failed(_ message: String) -> ProcessState {
        var copy = self
        copy.hasExited = true
        copy.failureMessage = message
        return copy
    }
}
