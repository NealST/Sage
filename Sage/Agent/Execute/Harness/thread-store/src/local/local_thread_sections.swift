//
//  local_thread_sections.swift
//  CodexThreadStore
//
//  Port of codex-rs/thread-store/src/local/thread_sections.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Filename is `local_thread_sections.swift` so SPM object-file basenames
//  do not collide with `thread-store/src/thread_sections.swift`. Section
//  catalog CRUD is a state-db path. There is no JSONL representation, so
//  every operation throws `unsupported` until GRDB lands.
//  `InMemoryThreadStore` already implements the catalog.
//

import Foundation

func listThreadSections(
    store: LocalThreadStore,
    params: ListThreadSectionsParams
) throws -> StoredThreadSectionsPage {
    _ = params
    throw unsupportedSection(store, operation: "threadSection/list")
}

func createThreadSection(
    store: LocalThreadStore,
    params: CreateThreadSectionParams
) throws -> StoredThreadSection {
    _ = params
    throw unsupportedSection(store, operation: "threadSection/create")
}

func renameThreadSection(
    store: LocalThreadStore,
    params: RenameThreadSectionParams
) throws -> StoredThreadSection? {
    _ = params
    throw unsupportedSection(store, operation: "threadSection/update")
}

func deleteThreadSection(
    store: LocalThreadStore,
    params: DeleteThreadSectionParams
) throws -> Bool {
    _ = params
    throw unsupportedSection(store, operation: "threadSection/delete")
}

private func unsupportedSection(
    _ store: LocalThreadStore,
    operation: String
) -> ThreadStoreError {
    _ = store
    return .unsupported(operation: operation)
}
