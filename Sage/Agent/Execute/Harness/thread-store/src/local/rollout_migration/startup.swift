//
//  startup.swift
//  CodexThreadStore
//
//  Port of codex-rs/thread-store/src/local/rollout_migration/startup.rs
//  (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  No-op when `stateDb` is absent (same as Rust). Inspection / cursor /
//  skip-list helpers are ported. Applying background migration throws until
//  GRDB projection exists.
//

import CodexProtocol
import CodexRollout
import CodexState
import Foundation

let LEGACY_TO_PAGINATED_MIGRATION_ID = "legacy_to_paginated_v1"
let EMPTY_SKIP_REASON = "empty"
let FAILED_SKIP_REASON = "failed"
let MALFORMED_SESSION_META_SKIP_REASON = "malformed_session_meta"
let BUSY_SKIP_REASON = "busy"
let CURSOR_LOOKBACK_SECONDS: Int64 = 48 * 60 * 60

struct RolloutFingerprint: Equatable {
    var sizeBytes: Int64 = 0
    var modifiedAtNs: Int64 = 0
}

enum StartupInspection {
    case paginated
    case legacy
    case needsMigration
    case skipped
    case unresolved
}

func runMigrateRolloutsOnStartup(store: LocalThreadStore) async throws {
    guard store.stateDb() != nil else { return }
    throw ThreadStoreError.unsupported(operation: "rollout_migration")
}

func inspectRolloutPath(store: LocalThreadStore, path: String) throws -> StartupInspection {
    _ = store
    let before = try rolloutFingerprint(path)
    do {
        let metadata = try readSessionMetaLine(path: path)
        return metadata.meta.historyMode == .legacy ? .legacy : .paginated
    } catch {
        let after = try rolloutFingerprint(path)
        if before != after { return .unresolved }
        if before.sizeBytes == 0 { return .needsMigration }
        return .skipped
    }
}

func threadCreationCursor(_ path: String) -> RolloutMigrationCursor? {
    var name = (path as NSString).lastPathComponent
    if name.hasSuffix(".jsonl.zst") {
        name = String(name.dropLast(".jsonl.zst".count))
    } else if name.hasSuffix(".jsonl") {
        name = String(name.dropLast(".jsonl".count))
    } else {
        return nil
    }
    guard name.hasPrefix("rollout-") else { return nil }
    let stem = String(name.dropFirst("rollout-".count))
    guard stem.count > 37 else { return nil }
    let separator = stem.count - 37
    let threadId = String(stem.suffix(36))
    guard (try? ThreadId.fromString(threadId)) != nil else { return nil }
    let stamp = String(stem.prefix(separator))
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
    guard let date = formatter.date(from: stamp) else { return nil }
    return RolloutMigrationCursor(
        threadCreatedAt: Int64(date.timeIntervalSince1970.rounded(.towardZero)),
        threadId: threadId
    )
}

func relativeRolloutPath(store: LocalThreadStore, path: String) -> String {
    let home = store.config.codexHome
    if path.hasPrefix(home + "/") {
        return String(path.dropFirst(home.count + 1)).replacingOccurrences(of: "\\", with: "/")
    }
    return path.replacingOccurrences(of: "\\", with: "/")
}

func plainRolloutFileName(_ path: String) -> String? {
    let name = (plainRolloutPath(path) as NSString).lastPathComponent
    return name.isEmpty ? nil : name
}

func rolloutFingerprint(_ path: String) throws -> RolloutFingerprint {
    let attributes: [FileAttributeKey: Any]
    do {
        attributes = try FileManager.default.attributesOfItem(atPath: path)
    } catch {
        throw migrationError(error)
    }
    let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
    let modified = (attributes[.modificationDate] as? Date) ?? Date(timeIntervalSince1970: 0)
    let nanos = modified.timeIntervalSince1970 * 1_000_000_000
    return RolloutFingerprint(
        sizeBytes: size,
        modifiedAtNs: Int64(nanos.rounded(.towardZero))
    )
}
