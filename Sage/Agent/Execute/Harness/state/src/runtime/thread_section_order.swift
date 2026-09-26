//
//  thread_section_order.swift
//  CodexState
//
//  Port of codex-rs/state/src/runtime/thread_section_order.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Section-order SQL throws until a state pool exists. An empty thread list
//  returns an empty map. `beforeThreadId` without a section is rejected
//  before the database is touched. Pinned section constants live in lib.swift.
//

import CodexProtocol
import Foundation

let SECTION_POSITION_GAP: Int64 = 1_000_000

extension StateRuntime {
    /// Read persisted section ordering for multiple threads in one SQLite query.
    public func getThreadSectionOrdering(
        threadIds: [ThreadId]
    ) async throws -> [ThreadId: (Int64?, Date?)] {
        if threadIds.isEmpty {
            return [:]
        }
        throw StateRuntimeError.sqliteUnavailable("thread_section_order")
    }

    /// Read an independently persisted thread section by its opaque identifier.
    public func getThreadSection(id: String) async throws -> ThreadSection? {
        _ = id
        throw StateRuntimeError.sqliteUnavailable("thread_section_order")
    }

    /// List independently persisted sections in stable, cursor-paginated identifier order.
    public func listThreadSections(
        cursor: String?,
        limit: Int
    ) async throws -> ThreadSectionsPage {
        _ = max(limit, 1)
        _ = cursor
        throw StateRuntimeError.sqliteUnavailable("thread_section_order")
    }

    /// Move a thread into or within a section, or clear its section.
    ///
    /// Omitting `beforeThreadId` appends the thread to its destination section.
    public func moveThreadToSection(
        threadId: ThreadId,
        section: String?,
        beforeThreadId: ThreadId?
    ) async throws -> Bool {
        if section == nil && beforeThreadId != nil {
            throw StateRuntimeError.invalidInput(
                "before thread cannot be specified without a section"
            )
        }
        _ = threadId
        _ = SECTION_POSITION_GAP
        throw StateRuntimeError.sqliteUnavailable("thread_section_order")
    }
}
