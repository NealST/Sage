//
//  move_thread_to_section.swift
//  CodexThreadStore
//
//  Port of codex-rs/thread-store/src/local/move_thread_to_section.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Rust only updates the SQLite state-db section/position pointer. There is
//  no JSONL representation, so after request validation this throws
//  `unsupported("thread/section/move")` until GRDB lands.
//

import CodexProtocol
import Foundation

func moveThreadToSection(
    store: LocalThreadStore,
    params: MoveThreadToSectionParams
) throws {
    if let section = params.section,
       section.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
        throw ThreadStoreError.invalidRequest("section must not be empty")
    }
    if params.section == nil && params.beforeThreadId != nil {
        throw ThreadStoreError.invalidRequest(
            "before thread cannot be specified without a section")
    }
    _ = store
    throw ThreadStoreError.unsupported(operation: "thread/section/move")
}
