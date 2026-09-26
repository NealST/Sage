//
//  thread_sections.swift
//  CodexState
//
//  Port of codex-rs/state/src/runtime/thread_sections.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  INSERT / UPDATE / DELETE SQL throws until a state pool exists. Pinned
//  section guards match upstream before the database is touched.
//

import CodexProtocol
import Foundation

extension StateRuntime {
    /// Create a custom thread section with a stable, server-assigned UUIDv7.
    public func createThreadSection(
        name: String,
        appearance: ThreadSectionAppearance? = nil
    ) async throws -> ThreadSection {
        _ = ThreadSection(
            id: ThreadId().description,
            name: name,
            appearance: appearance
        )
        throw StateRuntimeError.sqliteUnavailable("state")
    }

    /// Rename a custom thread section without changing its stable identity.
    public func renameThreadSection(
        id: String,
        name: String,
        appearance: ThreadSectionAppearance?? = nil
    ) async throws -> ThreadSection? {
        if id == PINNED_THREAD_SECTION_ID {
            throw StateRuntimeError.invalidInput(
                "built-in pinned thread section cannot be renamed"
            )
        }
        _ = name
        _ = appearance
        throw StateRuntimeError.sqliteUnavailable("state")
    }

    /// Delete a custom section and return its threads to the unsectioned list.
    public func deleteThreadSection(_ id: String) async throws -> Bool {
        if id == PINNED_THREAD_SECTION_ID {
            throw StateRuntimeError.invalidInput(
                "built-in pinned thread section cannot be deleted"
            )
        }
        throw StateRuntimeError.sqliteUnavailable("state")
    }
}
