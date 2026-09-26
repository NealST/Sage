//
//  list_threads.swift
//  CodexThreadStore
//
//  Port of codex-rs/thread-store/src/local/list_threads.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Working JSONL subset via `CodexRollout.getThreads` / `getThreadsInRoot`.
//  Archived listing uses the flat `archived_sessions/` layout (archive
//  moves files there without YYYY/MM/DD). Section-position sort,
//  state-DB-only listing, and spawn-graph filters throw `unsupported`.
//

import CodexProtocol
import CodexRollout
import Foundation

func listLocalThreads(
    store: LocalThreadStore,
    params: ListThreadsParams
) throws -> ThreadPage {
    if params.sortKey == .sectionPosition {
        throw ThreadStoreError.unsupported(operation: "list_threads_section_position")
    }
    if params.useStateDbOnly {
        throw ThreadStoreError.unsupported(operation: "list_threads_state_db_only")
    }
    if params.relationFilter != nil {
        throw ThreadStoreError.unsupported(operation: "list_threads_relation_filter")
    }

    let cursor: Cursor?
    if let raw = params.cursor {
        guard let parsed = parseCursor(raw) else {
            throw ThreadStoreError.invalidRequest("invalid cursor: \(raw)")
        }
        cursor = parsed
    } else {
        cursor = nil
    }

    let rolloutSort: CodexRollout.ThreadSortKey
    switch params.sortKey {
    case .createdAt: rolloutSort = .createdAt
    case .updatedAt: rolloutSort = .updatedAt
    case .recencyAt: rolloutSort = .recencyAt
    case .sectionPosition:
        throw ThreadStoreError.unsupported(operation: "list_threads_section_position")
    }

    let page: CodexRollout.ThreadsPage
    if params.archived {
        let root = (store.config.codexHome as NSString)
            .appendingPathComponent(ARCHIVED_SESSIONS_SUBDIR)
        page = try getThreadsInRoot(
            root: root,
            pageSize: params.pageSize,
            cursor: cursor,
            sortKey: rolloutSort,
            config: ThreadListConfig(
                allowedSources: params.allowedSources,
                modelProviders: params.modelProviders,
                cwdFilters: params.cwdFilters,
                defaultProvider: store.config.defaultModelProviderId,
                layout: .flat
            )
        )
    } else {
        page = try getThreads(
            codexHome: store.config.codexHome,
            pageSize: params.pageSize,
            cursor: cursor,
            sortKey: rolloutSort,
            allowedSources: params.allowedSources,
            modelProviders: params.modelProviders,
            cwdFilters: params.cwdFilters,
            defaultProvider: store.config.defaultModelProviderId
        )
    }

    var items = page.items.compactMap {
        storedThreadFromRolloutItem(
            $0,
            archived: params.archived,
            defaultProvider: store.config.defaultModelProviderId
        )
    }
    if params.sortDirection == .asc {
        items.reverse()
    }
    if let search = params.searchTerm?.trimmingCharacters(in: .whitespacesAndNewlines),
       !search.isEmpty
    {
        let needle = search.lowercased()
        items = items.filter { thread in
            thread.preview.lowercased().contains(needle)
                || (thread.name?.lowercased().contains(needle) ?? false)
                || (thread.firstUserMessage?.lowercased().contains(needle) ?? false)
        }
    }
    if let section = params.section {
        items = items.filter { $0.section?.id == section }
    }
    if let projectId = params.projectId {
        items = items.filter { $0.projectId == projectId }
    }

    return ThreadPage(items: items, nextCursor: encodeThreadCursor(page.nextCursor))
}

private func encodeThreadCursor(_ cursor: Cursor?) -> String? {
    guard let cursor else { return nil }
    guard let data = try? JSONEncoder().encode(cursor),
          let token = try? JSONDecoder().decode(String.self, from: data)
    else { return nil }
    return token
}
