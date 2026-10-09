//
//  clean_background_terminals.swift
//  Sage
//
//  Port of `clean_background_terminals` in
//  codex-rs/core/src/session/handlers.rs and
//  `Session::close_unified_exec_processes` in
//  codex-rs/core/src/tasks/mod.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Drains this thread's unified-exec processes and terminates each one.
//  Does not start a turn or abort the running turn. Network-approval
//  unregistration waits.
//

import CodexCore
import Foundation

extension Session {
    /// rust `Session::close_unified_exec_processes`.
    func closeUnifiedExecProcesses() async {
        await services.unifiedExecManager.terminateAllProcesses()
    }
}
