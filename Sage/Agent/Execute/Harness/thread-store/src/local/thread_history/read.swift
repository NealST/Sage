//
//  read.swift
//  CodexThreadStore
//
//  Port of codex-rs/thread-store/src/local/thread_history/read.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  `HistoryCursor` / `CursorScope` encode and decode as JSON (no sqlx).
//  `listTurns` / `listItems` run in-memory request checks, then throw
//  `unsupported("paginated_threads")` until GRDB can page SQLite rows.
//  sqlx row mappers (`stored_turn_row`, `StoredSummaryColumns`) are omitted.
//

import CodexProtocol
import Foundation

enum CursorScope: Equatable {
    case turns
    case itemsByCreatedAtOrdinal
    case itemsByUpdatedAtOrdinal
}

extension CursorScope: Codable {
    private enum CodingKeys: String, CodingKey { case kind }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
        case "turns":
            self = .turns
        case "itemsByCreatedAtOrdinal":
            self = .itemsByCreatedAtOrdinal
        case "itemsByUpdatedAtOrdinal":
            self = .itemsByUpdatedAtOrdinal
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "Unknown CursorScope: \(kind)")
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .turns:
            try container.encode("turns", forKey: .kind)
        case .itemsByCreatedAtOrdinal:
            try container.encode("itemsByCreatedAtOrdinal", forKey: .kind)
        case .itemsByUpdatedAtOrdinal:
            try container.encode("itemsByUpdatedAtOrdinal", forKey: .kind)
        }
    }
}

struct HistoryCursor: Codable, Equatable {
    var requestedThreadId: ThreadId
    var rolloutOrdinal: UInt64
    var includeAnchor: Bool
    var scope: CursorScope
}

struct RolloutHistoryPosition {
    var rolloutOrdinal: Int64
}

struct StoredTurnRow {
    var position: RolloutHistoryPosition
    var turnId: String
    var status: StoredTurnStatus
    var error: StoredTurnError?
    var startedAt: Int64?
    var completedAt: Int64?
    var durationMs: Int64?
    var firstUserItemId: String?
    var finalAgentItemId: String?
    var summaryItems: [StoredThreadItem]
}

struct StoredThreadItemRow {
    var position: RolloutHistoryPosition
    var item: StoredThreadItem
}

func listLocalTurns(
    store: LocalThreadStore,
    params: ListTurnsParams
) throws -> TurnPage {
    _ = store
    try validatePageSize(params.pageSize)
    _ = try parseCursor(params.cursor, requestedThreadId: params.threadId, scope: .turns)
    throw paginatedThreadsUnsupported()
}

func listLocalItems(
    store: LocalThreadStore,
    params: ListItemsParams
) throws -> ItemPage {
    _ = store
    try validatePageSize(params.pageSize)
    if params.sortKey == .updatedAtOrdinal, params.afterUpdatedAtOrdinal == nil {
        throw ThreadStoreError.invalidRequest(
            "update-ordinal item sorting requires an update watermark")
    }
    let scope: CursorScope =
        params.sortKey == .updatedAtOrdinal ? .itemsByUpdatedAtOrdinal : .itemsByCreatedAtOrdinal
    _ = try parseCursor(params.cursor, requestedThreadId: params.threadId, scope: scope)
    throw paginatedThreadsUnsupported()
}

func validateThreadForPaginatedReads(
    store: LocalThreadStore,
    threadId: ThreadId,
    includeArchived: Bool,
    operation: String
) throws {
    _ = (threadId, includeArchived)
    guard store.stateDb() != nil else {
        throw ThreadStoreError.unsupported(operation: operation)
    }
    throw paginatedThreadsUnsupported()
}

func parseCursor(
    _ cursor: String?,
    requestedThreadId: ThreadId,
    scope: CursorScope
) throws -> HistoryCursor? {
    guard let cursor else { return nil }
    let cursorValue: HistoryCursor
    do {
        cursorValue = try JSONDecoder().decode(HistoryCursor.self, from: Data(cursor.utf8))
    } catch {
        throw invalidCursor(cursor)
    }
    if cursorValue.requestedThreadId != requestedThreadId || cursorValue.scope != scope {
        throw invalidCursor(cursor)
    }
    return cursorValue
}

func serializeCursor(
    requestedThreadId: ThreadId,
    scope: CursorScope,
    rolloutOrdinal: Int64,
    includeAnchor: Bool
) throws -> String {
    guard let ordinal = UInt64(exactly: rolloutOrdinal) else {
        throw invalidCursor("negative rollout ordinal")
    }
    let encoded: Data
    do {
        encoded = try JSONEncoder().encode(
            HistoryCursor(
                requestedThreadId: requestedThreadId,
                rolloutOrdinal: ordinal,
                includeAnchor: includeAnchor,
                scope: scope
            ))
    } catch {
        throw threadHistoryError(error)
    }
    guard let token = String(data: encoded, encoding: .utf8) else {
        throw threadHistoryError("cursor is not valid UTF-8")
    }
    return token
}

func storedUpdatedAtOrdinal(_ updatedAtOrdinal: Int64) throws -> UInt64 {
    guard let ordinal = UInt64(exactly: updatedAtOrdinal) else {
        throw ThreadStoreError.internal(
            "invalid stored item updated-at ordinal: \(updatedAtOrdinal)")
    }
    return ordinal
}

func invalidCursor(_ cursor: String) -> ThreadStoreError {
    .invalidRequest("invalid cursor: \(cursor)")
}
