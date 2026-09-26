//
//  telemetry.swift
//  CodexState
//
//  Port of codex-rs/state/src/telemetry.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  sqlx / serde error classification is replaced with NSError + SQLite
//  primary-code mapping. Process-wide sink uses OSAllocatedUnfairLock.
//

import Foundation
import os

/// Errors encountered during DB operations. Tags: [stage]
public let DB_ERROR_METRIC = "codex.db.error"
/// Metrics on backfill process. Tags: [status]
public let DB_METRIC_BACKFILL = "codex.db.backfill"
/// Metrics on backfill duration. Tags: [status]
public let DB_METRIC_BACKFILL_DURATION_MS = "codex.db.backfill.duration_ms"
/// SQLite initialization attempts. Tags: [status, phase, db, error]
public let DB_INIT_METRIC = "codex.sqlite.init.count"
/// SQLite initialization latency. Tags: [status, phase, db, error]
public let DB_INIT_DURATION_METRIC = "codex.sqlite.init.duration_ms"
/// Rollout fallback attempts. Tags: [caller, reason]
public let DB_FALLBACK_METRIC = "codex.sqlite.fallback.count"
/// SQLite log batch write attempts. Tags: [status, error]
public let LOG_WRITE_METRIC = "codex.sqlite.logs.write.count"
/// SQLite log batch write latency. Tags: [status, error]
public let LOG_WRITE_DURATION_METRIC = "codex.sqlite.logs.write.duration_ms"
/// Estimated bytes in each SQLite log batch. Tags: [status, error]
public let LOG_WRITE_BYTES_METRIC = "codex.sqlite.logs.write.bytes"
/// Number of entries in each SQLite log batch. Tags: [status, error]
public let LOG_WRITE_ENTRIES_METRIC = "codex.sqlite.logs.write.entries"
/// Largest estimated entry size in each SQLite log batch. Tags: [status, error]
public let LOG_WRITE_MAX_ENTRY_BYTES_METRIC = "codex.sqlite.logs.write.max_entry_bytes"
/// SQLite log entries discarded before they can be queued. Tags: [reason]
public let LOG_QUEUE_DROPPED_METRIC = "codex.sqlite.logs.queue.dropped"

/// Low-cardinality sink for SQLite startup, fallback, and log-write telemetry.
///
/// Implementations should absorb delivery failures locally. Database behavior
/// must not depend on whether telemetry export succeeds.
public protocol DbTelemetry: Sendable {
    func counter(_ name: String, inc: Int64, tags: [(String, String)])
    func histogram(_ name: String, value: Int64, tags: [(String, String)])
    func recordDuration(_ name: String, duration: Duration, tags: [(String, String)])
}

public typealias DbTelemetryHandle = any DbTelemetry

/// No-op sink used until an OTEL exporter is installed.
public struct NoopDbTelemetry: DbTelemetry, Sendable {
    public init() {}

    public func counter(_ name: String, inc: Int64, tags: [(String, String)]) {}
    public func histogram(_ name: String, value: Int64, tags: [(String, String)]) {}
    public func recordDuration(_ name: String, duration: Duration, tags: [(String, String)]) {}
}

/// Process-wide no-op handle; `installProcessDbTelemetry` replaces it once.
public let NOOP_DB_TELEMETRY: DbTelemetryHandle = NoopDbTelemetry()

private let processDbTelemetry = OSAllocatedUnfairLock<DbTelemetryHandle?>(initialState: nil)

/// Install the process-wide SQLite telemetry sink.
///
/// Startup owners should call this once after OTEL initialization. Subsequent
/// installs are ignored and keep the first installed sink.
public func installProcessDbTelemetry(_ telemetry: DbTelemetryHandle) -> Bool {
    processDbTelemetry.withLock { current in
        if current != nil {
            return false
        }
        current = telemetry
        return true
    }
}

public enum DbKind: String, Equatable, Sendable {
    case state
    case logs
    case goals
    case memories
    case queue
    case threadHistory = "thread_history"

    public var asStr: String { rawValue }
}

func recordInitResult(
    telemetry: (any DbTelemetry)?,
    db: DbKind,
    phase: String,
    duration: Duration,
    succeeded: Bool,
    error: Error? = nil
) {
    let outcome = DbOutcomeTags.from(succeeded: succeeded, error: error)
    let tags = [
        ("status", outcome.status),
        ("phase", phase),
        ("db", db.asStr),
        ("error", outcome.error),
    ]
    recordCounter(telemetry, name: DB_INIT_METRIC, tags: tags)
    recordDuration(telemetry, name: DB_INIT_DURATION_METRIC, duration: duration, tags: tags)
}

public func recordBackfillGate(
    telemetry: (any DbTelemetry)?,
    duration: Duration,
    succeeded: Bool,
    error: Error? = nil
) {
    recordInitResult(
        telemetry: telemetry,
        db: .state,
        phase: "backfill_gate",
        duration: duration,
        succeeded: succeeded,
        error: error
    )
}

public func recordFallback(
    caller: String,
    reason: String,
    telemetryOverride: (any DbTelemetry)? = nil
) {
    recordCounter(
        telemetryOverride,
        name: DB_FALLBACK_METRIC,
        tags: [("caller", caller), ("reason", reason)]
    )
}

func recordLogWrite(
    telemetry: (any DbTelemetry)?,
    duration: Duration,
    entries: [LogEntry],
    succeeded: Bool,
    error: Error? = nil
) {
    guard let telemetry = resolveTelemetry(telemetry) else { return }

    let outcome = DbOutcomeTags.from(succeeded: succeeded, error: error)
    let tags = [("status", outcome.status), ("error", outcome.error)]
    var batchBytes: Int64 = 0
    var maxEntryBytes: Int64 = 0
    for entry in entries {
        let entryBytes = entry.estimatedBytes()
        batchBytes &+= entryBytes
        maxEntryBytes = max(maxEntryBytes, entryBytes)
    }
    let entryCount = Int64(clamping: entries.count)

    telemetry.counter(LOG_WRITE_METRIC, inc: 1, tags: tags)
    telemetry.recordDuration(LOG_WRITE_DURATION_METRIC, duration: duration, tags: tags)
    telemetry.histogram(LOG_WRITE_BYTES_METRIC, value: batchBytes, tags: tags)
    telemetry.histogram(LOG_WRITE_ENTRIES_METRIC, value: entryCount, tags: tags)
    telemetry.histogram(LOG_WRITE_MAX_ENTRY_BYTES_METRIC, value: maxEntryBytes, tags: tags)
}

func recordLogQueueDrop(reason: String, telemetry: (any DbTelemetry)?) {
    recordCounter(telemetry, name: LOG_QUEUE_DROPPED_METRIC, tags: [("reason", reason)])
}

private func recordCounter(
    _ telemetry: (any DbTelemetry)?,
    name: String,
    tags: [(String, String)]
) {
    resolveTelemetry(telemetry)?.counter(name, inc: 1, tags: tags)
}

private func recordDuration(
    _ telemetry: (any DbTelemetry)?,
    name: String,
    duration: Duration,
    tags: [(String, String)]
) {
    resolveTelemetry(telemetry)?.recordDuration(name, duration: duration, tags: tags)
}

private func resolveTelemetry(_ telemetry: (any DbTelemetry)?) -> (any DbTelemetry)? {
    if let telemetry { return telemetry }
    return processDbTelemetry.withLock { $0 }
}

private struct DbOutcomeTags {
    var status: String
    var error: String

    static func from(succeeded: Bool, error: Error?) -> DbOutcomeTags {
        if succeeded {
            return DbOutcomeTags(status: "success", error: "none")
        }
        return DbOutcomeTags(status: "failed", error: classifyError(error))
    }
}

func classifyError(_ error: Error?) -> String {
    guard let error else { return "unknown" }
    let nsError = error as NSError
    let combined = "\(nsError.domain) \(nsError.localizedDescription) \(String(describing: error))"
        .lowercased()
    if combined.contains("migrat") {
        return "migration"
    }
    if combined.contains("json") || combined.contains("serializ") || combined.contains("decod") {
        return "serde"
    }
    if nsError.domain == NSPOSIXErrorDomain || nsError.domain == NSCocoaErrorDomain {
        if let sqlite = classifySqliteCode(String(nsError.code)) {
            return sqlite
        }
        return "io"
    }
    if let sqlite = classifySqliteCode(String(nsError.code)) {
        return sqlite
    }
    return "unknown"
}

/// SQLite result codes: https://www.sqlite.org/rescode.html
/// Extended codes preserve the primary code in the low byte.
func classifySqliteCode(_ code: String) -> String? {
    guard let parsed = Int32(code) else { return nil }
    switch parsed & 0xff {
    case 5: return "busy"
    case 6: return "locked"
    case 8: return "readonly"
    case 10: return "io"
    case 11: return "corrupt"
    case 13: return "full"
    case 14: return "cantopen"
    case 17: return "schema"
    case 19: return "constraint"
    default: return nil
    }
}
