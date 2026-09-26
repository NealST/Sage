//
//  search_threads.swift
//  CodexThreadStore
//
//  Port of codex-rs/thread-store/src/local/search_threads.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Uses `searchRolloutMatches` + `firstRolloutContentMatchSnippet`.
//  Empty `searchTerm` and `SectionPosition` sort are `invalidRequest`.
//  State-DB name/section overlay (`resolve_thread_names` /
//  `resolve_thread_section_metadata`) is not ported; names come from
//  JSONL metadata only.
//

import CodexProtocol
import CodexRollout
import Foundation

private struct ThreadSearchItem {
    var item: ThreadItem
    var snippet: String
}

func searchLocalThreads(
    store: LocalThreadStore,
    params: SearchThreadsParams
) throws -> ThreadSearchPage {
    let searchTerm = params.searchTerm
    if searchTerm.isEmpty {
        throw ThreadStoreError.invalidRequest("thread/search requires search_term")
    }

    var pageCursor: CodexRollout.Cursor?
    if let raw = params.cursor {
        guard let parsed = parseCursor(raw) else {
            throw ThreadStoreError.invalidRequest("invalid cursor: \(raw)")
        }
        pageCursor = parsed
    }

    let rolloutSort: CodexRollout.ThreadSortKey
    switch params.sortKey {
    case .createdAt:
        rolloutSort = .createdAt
    case .updatedAt:
        rolloutSort = .updatedAt
    case .recencyAt:
        rolloutSort = .recencyAt
    case .sectionPosition:
        throw ThreadStoreError.invalidRequest(
            "section-position sorting requires a section filter")
    }

    let matchingRollouts: RolloutSearchMatches
    do {
        matchingRollouts = try searchRolloutMatches(
            codexHome: store.config.codexHome,
            archived: params.archived,
            searchTerm: searchTerm
        )
    } catch {
        throw ThreadStoreError.internal(
            "failed to search rollout contents: \(error)")
    }
    if matchingRollouts.isEmpty {
        return ThreadSearchPage(items: [], nextCursor: nil)
    }

    var remainingRollouts: [String: String?] = [:]
    for (path, snippet) in matchingRollouts {
        remainingRollouts[rolloutSearchPath(path)] = snippet
    }

    var matchingItems: [ThreadSearchItem] = []
    let scanPageSize = min(max(params.pageSize * 8, 256), 2048)

    while true {
        let page: ThreadsPage
        if params.archived {
            let root = (store.config.codexHome as NSString)
                .appendingPathComponent(ARCHIVED_SESSIONS_SUBDIR)
            page = try getThreadsInRoot(
                root: root,
                pageSize: scanPageSize,
                cursor: pageCursor,
                sortKey: rolloutSort,
                config: ThreadListConfig(
                    allowedSources: params.allowedSources,
                    modelProviders: nil,
                    cwdFilters: nil,
                    defaultProvider: store.config.defaultModelProviderId,
                    layout: .flat
                )
            )
        } else {
            page = try getThreads(
                codexHome: store.config.codexHome,
                pageSize: scanPageSize,
                cursor: pageCursor,
                sortKey: rolloutSort,
                allowedSources: params.allowedSources,
                modelProviders: nil,
                cwdFilters: nil,
                defaultProvider: store.config.defaultModelProviderId
            )
        }

        var items = page.items
        if params.sortDirection == .asc {
            items.reverse()
        }

        for item in items {
            let logicalPath = rolloutSearchPath(item.path)
            guard let snippetOrNil = remainingRollouts.removeValue(forKey: logicalPath) else {
                continue
            }
            let snippet: String
            if let existing = snippetOrNil {
                snippet = existing
            } else {
                let read: String?
                do {
                    read = try firstRolloutContentMatchSnippet(
                        path: item.path, searchTerm: searchTerm
                    )
                } catch {
                    throw ThreadStoreError.internal(
                        "failed to read rollout search match: \(error)")
                }
                guard let read else { continue }
                snippet = read
            }
            matchingItems.append(ThreadSearchItem(item: item, snippet: snippet))
            if matchingItems.count > params.pageSize {
                break
            }
        }

        pageCursor = page.nextCursor
        if matchingItems.count > params.pageSize
            || remainingRollouts.isEmpty
            || pageCursor == nil
        {
            break
        }
    }

    if matchingItems.isEmpty {
        for (path, snippetOrNil) in matchingRollouts {
            guard let item = readThreadItemFromRollout(path: path) else { continue }
            let snippet: String
            if let existing = snippetOrNil {
                snippet = existing
            } else if let read = try? firstRolloutContentMatchSnippet(
                path: path, searchTerm: searchTerm
            ) {
                snippet = read
            } else {
                snippet = searchTerm
            }
            matchingItems.append(ThreadSearchItem(item: item, snippet: snippet))
            if matchingItems.count >= params.pageSize { break }
        }
    }

    let moreMatchesAvailable = matchingItems.count > params.pageSize
    if matchingItems.count > params.pageSize {
        matchingItems = Array(matchingItems.prefix(params.pageSize))
    }
    let nextCursor: String?
    if moreMatchesAvailable, let last = matchingItems.last,
       let cursor = cursorFromThreadSearchItem(last, sortKey: params.sortKey)
    {
        nextCursor = encodeCursorToken(cursor)
    } else {
        nextCursor = nil
    }

    let items = matchingItems.compactMap { item -> StoredThreadSearchResult? in
        guard let thread = storedThreadFromRolloutItem(
            item.item,
            archived: params.archived,
            defaultProvider: store.config.defaultModelProviderId
        ) else {
            return nil
        }
        return StoredThreadSearchResult(thread: thread, snippet: item.snippet)
    }

    return ThreadSearchPage(items: items, nextCursor: nextCursor)
}

private func rolloutSearchPath(_ path: String) -> String {
    URL(fileURLWithPath: plainRolloutPath(path)).resolvingSymlinksInPath().path
}

private func cursorFromThreadSearchItem(
    _ item: ThreadSearchItem,
    sortKey: ThreadSortKey
) -> CodexRollout.Cursor? {
    let timestamp: String
    switch sortKey {
    case .createdAt:
        guard let created = item.item.createdAt else { return nil }
        timestamp = created
    case .updatedAt:
        guard let updated = item.item.updatedAt ?? item.item.createdAt else { return nil }
        timestamp = updated
    case .recencyAt:
        guard let recency = item.item.recencyAt ?? item.item.updatedAt ?? item.item.createdAt else {
            return nil
        }
        timestamp = recency
    case .sectionPosition:
        return nil
    }
    switch sortKey {
    case .recencyAt:
        guard let threadId = item.item.threadId else { return nil }
        return parseCursor("\(timestamp)|\(threadId)")
    case .createdAt, .updatedAt:
        return parseCursor(timestamp)
    case .sectionPosition:
        return nil
    }
}

private func encodeCursorToken(_ cursor: CodexRollout.Cursor) -> String? {
    guard let data = try? JSONEncoder().encode(cursor),
          let token = try? JSONDecoder().decode(String.self, from: data)
    else { return nil }
    return token
}
