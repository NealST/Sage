//
//  segment_paging.swift
//  CodexThreadStore
//
//  Port of codex-rs/thread-store/src/local/thread_history/segment_paging.rs
//  (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Page-size validation and JSON cursor helpers are in-memory. SQL segment
//  paging (`page_turn_rows`, `page_item_rows`) throws until GRDB. No schema
//  is invented.
//

import CodexProtocol
import Foundation

struct SegmentPage<T> {
    var rows: [T]
    var nextCursor: String?
    var backwardsCursor: String?
}

func validatePageSize(_ pageSize: Int) throws {
    if pageSize == 0 {
        throw ThreadStoreError.invalidRequest("page size must be positive")
    }
    let (limit, overflow) = pageSize.addingReportingOverflow(1)
    if overflow {
        throw pageSizeTooLarge()
    }
    guard Int64(exactly: limit) != nil else {
        throw pageSizeTooLarge()
    }
}

func pageTurnRows(
    requestedThreadId: ThreadId,
    lineage: RolloutLineage,
    cursor: String?,
    pageSize: Int,
    direction: SortDirection,
    itemsView: StoredTurnItemsView
) throws -> SegmentPage<StoredTurnRow> {
    _ = (requestedThreadId, lineage, cursor, pageSize, direction, itemsView)
    throw paginatedThreadsUnsupported()
}

func pageItemRows(
    lineage: RolloutLineage,
    params: ListItemsParams
) throws -> SegmentPage<StoredThreadItemRow> {
    if params.afterUpdatedAtOrdinal != nil && lineage.segments.count > 1 {
        throw ThreadStoreError.invalidRequest(
            "incremental item replay is not supported for forked threads")
    }
    if params.sortKey == .updatedAtOrdinal {
        guard params.afterUpdatedAtOrdinal != nil else {
            throw ThreadStoreError.invalidRequest(
                "update-ordinal item sorting requires an update watermark")
        }
        if lineage.segments.count != 1 {
            throw ThreadStoreError.internal(
                "update-ordinal item paging requires one rollout segment")
        }
    }
    throw paginatedThreadsUnsupported()
}

func segmentsFromCursor(
    lineage: RolloutLineage,
    direction: SortDirection,
    cursor: HistoryCursor?
) throws -> [(Int, RolloutLineageSegment, HistoryCursor?)] {
    let segments = lineage.segments
    let cursorIndex: Int?
    if let cursor {
        guard let index = lineage.segmentIndexForOrdinal(cursor.rolloutOrdinal) else {
            throw invalidCursor("position outside thread lineage")
        }
        cursorIndex = index
    } else {
        cursorIndex = nil
    }
    let indexes: [Int]
    switch direction {
    case .asc:
        indexes = Array((cursorIndex ?? 0)..<segments.count)
    case .desc:
        if segments.isEmpty {
            indexes = []
        } else {
            let end = cursorIndex ?? (segments.count - 1)
            indexes = Array((0...end).reversed())
        }
    }
    return indexes.map { index in
        let segmentCursor = index == cursorIndex ? cursor : nil
        return (index, segments[index], segmentCursor)
    }
}

func remainingLimit(pageSize: Int, rowCount: Int) throws -> Int64 {
    let (plusOne, overflowAdd) = pageSize.addingReportingOverflow(1)
    if overflowAdd {
        throw pageSizeTooLarge()
    }
    let (limit, overflowSub) = plusOne.subtractingReportingOverflow(rowCount)
    if overflowSub {
        throw pageSizeTooLarge()
    }
    guard let converted = Int64(exactly: limit) else {
        throw pageSizeTooLarge()
    }
    return converted
}

func finishPage<T: HasPosition>(
    requestedThreadId: ThreadId,
    scope: CursorScope,
    rows: [T],
    pageSize: Int
) throws -> SegmentPage<T> {
    var rows = rows
    let hasMore = rows.count > pageSize
    if rows.count > pageSize {
        rows = Array(rows.prefix(pageSize))
    }
    let backwardsCursor = try rows.first.map { row in
        try serializeCursor(
            requestedThreadId: requestedThreadId,
            scope: scope,
            rolloutOrdinal: row.positionValue.rolloutOrdinal,
            includeAnchor: true
        )
    }
    let nextCursor: String?
    if hasMore {
        nextCursor = try rows.last.map { row in
            try serializeCursor(
                requestedThreadId: requestedThreadId,
                scope: scope,
                rolloutOrdinal: row.positionValue.rolloutOrdinal,
                includeAnchor: false
            )
        }
    } else {
        nextCursor = nil
    }
    return SegmentPage(rows: rows, nextCursor: nextCursor, backwardsCursor: backwardsCursor)
}

protocol HasPosition {
    /// Rust `HasPosition::position`. Named `positionValue` so it does not
    /// collide with `StoredTurnRow.position` / `StoredThreadItemRow.position`.
    var positionValue: RolloutHistoryPosition { get }
}

extension StoredTurnRow: HasPosition {
    var positionValue: RolloutHistoryPosition { position }
}

extension StoredThreadItemRow: HasPosition {
    var positionValue: RolloutHistoryPosition { position }
}

func sqliteInteger(_ value: UInt64) throws -> Int64 {
    guard let converted = Int64(exactly: value) else {
        throw ThreadStoreError.invalidRequest(
            "rollout ordinal exceeds SQLite integer range")
    }
    return converted
}

func pageSizeTooLarge() -> ThreadStoreError {
    .invalidRequest("page size is too large")
}
