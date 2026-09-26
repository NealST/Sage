//
//  realtime.swift
//  CodexThreadStore
//
//  Port of codex-rs/thread-store/src/local/thread_history/realtime.rs
//  (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  `TimelineCursor` encode/decode and `entryKey` are JSON-only.
//  `ThreadTimelineEntry` is the store stub (`payload: JSONValue`); `entryKey`
//  reads camelCase `type` / `position` / `turnId` / nested `item.id`.
//  `listTimeline` validates page size and cursor, then throws until GRDB.
//

import CodexProtocol
import Foundation

struct TimelineCursor: Codable, Equatable {
    var threadId: ThreadId
    var position: UInt64
    var kind: UInt8
    var id: String
}

/// A rollout record can materialize both an item and a turn boundary. Keep the
/// boundary order stable, including when the page cuts through one ordinal.
func entryKey(_ entry: ThreadTimelineEntry) -> (UInt64, UInt8, String) {
    let object = entry.payload.objectValue ?? [:]
    let type = object["type"]?.stringValue ?? ""
    let position = jsonAsUInt64(object["position"]) ?? 0
    switch type {
    case "turnStarted":
        return (position, 0, object["turnId"]?.stringValue ?? "")
    case "item":
        return (position, 1, object["item"]?.objectValue?["id"]?.stringValue ?? "")
    case "realtime":
        return (position, 2, object["item"]?.objectValue?["id"]?.stringValue ?? "")
    case "turnCompleted":
        return (position, 3, object["turnId"]?.stringValue ?? "")
    default:
        return (0, 0, "")
    }
}

func listLocalTimeline(
    store: LocalThreadStore,
    params: ListTimelineParams
) throws -> TimelinePage {
    _ = store
    try validatePageSize(params.pageSize)
    if let raw = params.cursor {
        let cursor: TimelineCursor
        do {
            cursor = try JSONDecoder().decode(TimelineCursor.self, from: Data(raw.utf8))
        } catch {
            throw ThreadStoreError.invalidRequest("invalid thread timeline cursor")
        }
        if cursor.threadId != params.threadId {
            throw ThreadStoreError.invalidRequest(
                "thread timeline cursor belongs to another thread")
        }
    }
    throw paginatedThreadsUnsupported()
}

func jsonAsUInt64(_ value: JSONValue?) -> UInt64? {
    guard let value else { return nil }
    switch value {
    case .uint(let raw):
        return raw
    case .int(let raw) where raw >= 0:
        return UInt64(raw)
    default:
        return nil
    }
}
