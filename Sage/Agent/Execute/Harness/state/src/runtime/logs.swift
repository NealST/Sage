//
//  logs.swift
//  CodexState
//
//  Port of codex-rs/state/src/runtime/logs.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  SQLite methods throw until GRDB.
//

import Foundation

let LOG_RETENTION_DAYS: Int64 = 10

struct FeedbackLogRow: Equatable, Sendable {
    var ts: Int64
    var tsNanos: Int64
    var level: String
    var feedbackLogBody: String
}

enum LogSqlValue: Equatable, Sendable {
    case int64(Int64)
    case text(String)
}

/// In-memory stand-in for sqlx `QueryBuilder<Sqlite>` used by log filters.
struct LogQueryBuilder: Equatable, Sendable {
    var sql: String
    var binds: [LogSqlValue]

    init(_ sql: String = "") {
        self.sql = sql
        self.binds = []
    }

    mutating func push(_ fragment: String) {
        sql += fragment
    }

    mutating func pushBind(_ value: LogSqlValue) {
        sql += "?"
        binds.append(value)
    }

    mutating func pushBind(_ value: Int64) {
        pushBind(.int64(value))
    }

    mutating func pushBind(_ value: String) {
        pushBind(.text(value))
    }
}

func formatFeedbackLogLine(
    ts: Int64,
    tsNanos: Int64,
    level: String,
    feedbackLogBody: String
) -> String {
    let nanos: UInt32
    if let value = UInt32(exactly: tsNanos) {
        nanos = value
    } else {
        nanos = 0
    }
    let timestamp: String
    if let formatted = formatFeedbackTimestamp(ts: ts, nanos: nanos) {
        timestamp = formatted
    } else {
        timestamp = "\(ts).\(padSignedWidth9(tsNanos))Z"
    }
    let paddedLevel: String
    if level.count >= 5 {
        paddedLevel = level
    } else {
        paddedLevel = String(repeating: " ", count: 5 - level.count) + level
    }
    var line = "\(timestamp) \(paddedLevel) \(feedbackLogBody)"
    if !line.hasSuffix("\n") {
        line.append("\n")
    }
    return line
}

func formatFeedbackTimestamp(ts: Int64, nanos: UInt32) -> String? {
    let date = Date(timeIntervalSince1970: TimeInterval(ts))
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let parts = calendar.dateComponents(
        [.year, .month, .day, .hour, .minute, .second],
        from: date
    )
    guard
        let year = parts.year,
        let month = parts.month,
        let day = parts.day,
        let hour = parts.hour,
        let minute = parts.minute,
        let second = parts.second
    else {
        return nil
    }
    let micros = nanos / 1_000
    return String(
        format: "%04d-%02d-%02dT%02d:%02d:%02d.%06uZ",
        year,
        month,
        day,
        hour,
        minute,
        second,
        micros
    )
}

func padSignedWidth9(_ value: Int64) -> String {
    if value >= 0 {
        let digits = String(value)
        return String(repeating: "0", count: max(0, 9 - digits.count)) + digits
    }
    let digits = String(-value)
    return "-" + String(repeating: "0", count: max(0, 8 - digits.count)) + digits
}

func pushLogFilters(_ builder: inout LogQueryBuilder, query: LogQuery) {
    if !query.levelsUpper.isEmpty {
        builder.push(" AND UPPER(level) IN (")
        for (index, levelUpper) in query.levelsUpper.enumerated() {
            if index > 0 {
                builder.push(", ")
            }
            builder.pushBind(levelUpper)
        }
        builder.push(")")
    }
    if let fromTs = query.fromTs {
        builder.push(" AND ts >= ")
        builder.pushBind(fromTs)
    }
    if let toTs = query.toTs {
        builder.push(" AND ts <= ")
        builder.pushBind(toTs)
    }
    pushLikeFilters(&builder, column: "module_path", filters: query.moduleLike)
    pushLikeFilters(&builder, column: "file", filters: query.fileLike)
    let hasThreadFilter = !query.threadIds.isEmpty || query.includeThreadless
    if hasThreadFilter {
        builder.push(" AND (")
        var needsOr = false
        for threadId in query.threadIds {
            if needsOr {
                builder.push(" OR ")
            }
            builder.push("thread_id = ")
            builder.pushBind(threadId)
            needsOr = true
        }
        if query.includeThreadless {
            if needsOr {
                builder.push(" OR ")
            }
            builder.push("thread_id IS NULL")
        }
        builder.push(")")
    }
    if let afterId = query.afterId {
        builder.push(" AND id > ")
        builder.pushBind(afterId)
    }
    if let search = query.search {
        builder.push(" AND INSTR(COALESCE(feedback_log_body, ''), ")
        builder.pushBind(search)
        builder.push(") > 0")
    }
}

func pushLikeFilters(
    _ builder: inout LogQueryBuilder,
    column: String,
    filters: [String]
) {
    if filters.isEmpty {
        return
    }
    builder.push(" AND (")
    for (idx, filter) in filters.enumerated() {
        if idx > 0 {
            builder.push(" OR ")
        }
        builder.push(column)
        builder.push(" LIKE '%' || ")
        builder.pushBind(filter)
        builder.push(" || '%'")
    }
    builder.push(")")
}

func queryLogsSQL(_ query: LogQuery) -> LogQueryBuilder {
    var builder = LogQueryBuilder(
        "SELECT id, ts, ts_nanos, level, target, feedback_log_body AS message, thread_id, process_uuid, file, line FROM logs WHERE 1 = 1"
    )
    pushLogFilters(&builder, query: query)
    if query.descending {
        builder.push(" ORDER BY id DESC")
    } else {
        builder.push(" ORDER BY id ASC")
    }
    if let limit = query.limit {
        builder.push(" LIMIT ")
        builder.pushBind(Int64(limit))
    }
    return builder
}

func maxLogIdSQL(_ query: LogQuery) -> LogQueryBuilder {
    var builder = LogQueryBuilder("SELECT MAX(id) AS max_id FROM logs WHERE 1 = 1")
    pushLogFilters(&builder, query: query)
    return builder
}

func queryFeedbackLogsForThreadsSQL(_ threadIds: [String]) -> LogQueryBuilder {
    var builder = LogQueryBuilder(
        """

        WITH requested_threads(thread_id) AS (
            VALUES
        """
    )
    for (index, threadId) in threadIds.enumerated() {
        if index > 0 {
            builder.push(", ")
        }
        builder.push("(")
        builder.pushBind(threadId)
        builder.push(")")
    }
    builder.push(
        """

        ),
        latest_processes AS (
            SELECT (
                SELECT process_uuid
                FROM logs
                WHERE logs.thread_id = requested_threads.thread_id AND process_uuid IS NOT NULL
                ORDER BY ts DESC, ts_nanos DESC, id DESC
                LIMIT 1
            ) AS process_uuid
            FROM requested_threads
        ),
        feedback_logs AS (
            SELECT ts, ts_nanos, level, feedback_log_body, estimated_bytes, id
            FROM logs
            WHERE feedback_log_body IS NOT NULL AND (
                thread_id IN (SELECT thread_id FROM requested_threads)
                OR (
                    thread_id IS NULL
                    AND process_uuid IN (
                        SELECT process_uuid
                        FROM latest_processes
                        WHERE process_uuid IS NOT NULL
                    )
                )
            )
        ),
        bounded_feedback_logs AS (
            SELECT
                ts,
                ts_nanos,
                level,
                feedback_log_body,
                id,
                SUM(estimated_bytes) OVER (
                    ORDER BY ts DESC, ts_nanos DESC, id DESC
                ) AS cumulative_estimated_bytes
            FROM feedback_logs
        )
        SELECT ts, ts_nanos, level, feedback_log_body
        FROM bounded_feedback_logs
        WHERE cumulative_estimated_bytes <=
        """
    )
    builder.pushBind(LOG_PARTITION_SIZE_LIMIT_BYTES)
    builder.push(" ORDER BY ts DESC, ts_nanos DESC, id DESC")
    return builder
}

func logPartitionThreadIds(_ entries: [LogEntry]) -> [String] {
    Array(Set(entries.compactMap(\.threadId))).sorted()
}

func logPartitionThreadlessProcessUuids(_ entries: [LogEntry]) -> [String] {
    Array(
        Set(
            entries
                .filter { $0.threadId == nil }
                .compactMap(\.processUuid)
        )
    ).sorted()
}

func logPartitionHasThreadlessNullProcessUuid(_ entries: [LogEntry]) -> Bool {
    entries.contains { $0.threadId == nil && $0.processUuid == nil }
}

func logPartitionExceedsLimit(totalBytes: Int64?, rowCount: Int64) -> Bool {
    (totalBytes ?? 0) > LOG_PARTITION_SIZE_LIMIT_BYTES || rowCount > LOG_PARTITION_ROW_LIMIT
}

func overLimitThreadsPrecheckSQL(_ threadIds: [String]) -> LogQueryBuilder {
    var builder = LogQueryBuilder("SELECT thread_id FROM logs WHERE thread_id IN (")
    for (index, threadId) in threadIds.enumerated() {
        if index > 0 {
            builder.push(", ")
        }
        builder.pushBind(threadId)
    }
    builder.push(") GROUP BY thread_id HAVING SUM(")
    builder.push("estimated_bytes")
    builder.push(") > ")
    builder.pushBind(LOG_PARTITION_SIZE_LIMIT_BYTES)
    builder.push(" OR COUNT(*) > ")
    builder.pushBind(LOG_PARTITION_ROW_LIMIT)
    return builder
}

func overLimitThreadlessProcessesPrecheckSQL(_ processUuids: [String]) -> LogQueryBuilder {
    var builder = LogQueryBuilder(
        "SELECT process_uuid FROM logs WHERE thread_id IS NULL AND process_uuid IN ("
    )
    for (index, processUuid) in processUuids.enumerated() {
        if index > 0 {
            builder.push(", ")
        }
        builder.pushBind(processUuid)
    }
    builder.push(") GROUP BY process_uuid HAVING SUM(")
    builder.push("estimated_bytes")
    builder.push(") > ")
    builder.pushBind(LOG_PARTITION_SIZE_LIMIT_BYTES)
    builder.push(" OR COUNT(*) > ")
    builder.pushBind(LOG_PARTITION_ROW_LIMIT)
    return builder
}

func pruneOverLimitThreadsSQL(_ threadIds: [String]) -> LogQueryBuilder {
    var builder = LogQueryBuilder(
        """

        DELETE FROM logs
        WHERE id IN (
            SELECT id
            FROM (
                SELECT
                    id,
                    SUM(
        """
    )
    builder.push("estimated_bytes")
    builder.push(
        """

                    ) OVER (
                        PARTITION BY thread_id
                        ORDER BY ts DESC, ts_nanos DESC, id DESC
                    ) AS cumulative_bytes,
                    ROW_NUMBER() OVER (
                        PARTITION BY thread_id
                        ORDER BY ts DESC, ts_nanos DESC, id DESC
                    ) AS row_number
                FROM logs
                WHERE thread_id IN (
        """
    )
    for (index, threadId) in threadIds.enumerated() {
        if index > 0 {
            builder.push(", ")
        }
        builder.pushBind(threadId)
    }
    builder.push(
        """

                )
            )
            WHERE cumulative_bytes >
        """
    )
    builder.pushBind(LOG_PARTITION_SIZE_LIMIT_BYTES)
    builder.push(" OR row_number > ")
    builder.pushBind(LOG_PARTITION_ROW_LIMIT)
    builder.push("\n)")
    return builder
}

func pruneThreadlessProcessLogsSQL(_ processUuids: [String]) -> LogQueryBuilder {
    var builder = LogQueryBuilder(
        """

        DELETE FROM logs
        WHERE id IN (
            SELECT id
            FROM (
                SELECT
                    id,
                    SUM(
        """
    )
    builder.push("estimated_bytes")
    builder.push(
        """

                    ) OVER (
                        PARTITION BY process_uuid
                        ORDER BY ts DESC, ts_nanos DESC, id DESC
                    ) AS cumulative_bytes,
                    ROW_NUMBER() OVER (
                        PARTITION BY process_uuid
                        ORDER BY ts DESC, ts_nanos DESC, id DESC
                    ) AS row_number
                FROM logs
                WHERE thread_id IS NULL
                  AND process_uuid IN (
        """
    )
    for (index, processUuid) in processUuids.enumerated() {
        if index > 0 {
            builder.push(", ")
        }
        builder.pushBind(processUuid)
    }
    builder.push(
        """

                  )
            )
            WHERE cumulative_bytes >
        """
    )
    builder.pushBind(LOG_PARTITION_SIZE_LIMIT_BYTES)
    builder.push(" OR row_number > ")
    builder.pushBind(LOG_PARTITION_ROW_LIMIT)
    builder.push("\n)")
    return builder
}

func pruneThreadlessNullProcessLogsSQL() -> LogQueryBuilder {
    var builder = LogQueryBuilder(
        """

        DELETE FROM logs
        WHERE id IN (
            SELECT id
            FROM (
                SELECT
                    id,
                    SUM(
        """
    )
    builder.push("estimated_bytes")
    builder.push(
        """

                    ) OVER (
                        PARTITION BY process_uuid
                        ORDER BY ts DESC, ts_nanos DESC, id DESC
                    ) AS cumulative_bytes,
                    ROW_NUMBER() OVER (
                        PARTITION BY process_uuid
                        ORDER BY ts DESC, ts_nanos DESC, id DESC
                    ) AS row_number
                FROM logs
                WHERE thread_id IS NULL
                  AND process_uuid IS NULL
            )
            WHERE cumulative_bytes >
        """
    )
    builder.pushBind(LOG_PARTITION_SIZE_LIMIT_BYTES)
    builder.push(" OR row_number > ")
    builder.pushBind(LOG_PARTITION_ROW_LIMIT)
    builder.push("\n)")
    return builder
}

func nullProcessUsageSQL() -> LogQueryBuilder {
    var builder = LogQueryBuilder("SELECT SUM(")
    builder.push("estimated_bytes")
    builder.push(
        ") AS total_bytes, COUNT(*) AS row_count FROM logs WHERE thread_id IS NULL AND process_uuid IS NULL"
    )
    return builder
}

extension StateRuntime {
    /// Enforce per-partition retained-log-content caps after a successful batch insert.
    ///
    /// Thread logs are capped per `threadId`. Threadless process logs are
    /// capped per `processUuid`, including `processUuid == nil` as its own
    /// partition.
    func pruneLogsAfterInsert(_ entries: [LogEntry]) async throws {
        let threadIds = logPartitionThreadIds(entries)
        let processUuids = logPartitionThreadlessProcessUuids(entries)
        let hasNull = logPartitionHasThreadlessNullProcessUuid(entries)
        if threadIds.isEmpty && processUuids.isEmpty && !hasNull {
            return
        }
        _ = overLimitThreadsPrecheckSQL(threadIds)
        _ = overLimitThreadlessProcessesPrecheckSQL(processUuids)
        _ = pruneOverLimitThreadsSQL(threadIds)
        _ = pruneThreadlessProcessLogsSQL(processUuids)
        _ = pruneThreadlessNullProcessLogsSQL()
        _ = nullProcessUsageSQL()
        throw StateRuntimeError.sqliteUnavailable("logs")
    }

    func deleteLogsBefore(_ cutoffTs: Int64) async throws -> UInt64 {
        _ = cutoffTs
        throw StateRuntimeError.sqliteUnavailable("logs")
    }

    func runLogsStartupMaintenance() async throws {
        let cutoff = Date().addingTimeInterval(TimeInterval(-LOG_RETENTION_DAYS * 24 * 60 * 60))
        _ = try await deleteLogsBefore(Int64(cutoff.timeIntervalSince1970.rounded(.towardZero)))
    }
}
