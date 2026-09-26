//
//  log_db.swift
//  CodexState
//
//  Port of codex-rs/state/src/log_db.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Tracing-subscriber Layer / sqlx write path is deferred. `LogDbLayer` keeps
//  the public start / flush / failure-reporter API. Open and query methods
//  on `StateRuntime` throw until a GRDB logs pool exists. Partition caps
//  (`LOG_PARTITION_SIZE_LIMIT_BYTES`, `LOG_PARTITION_ROW_LIMIT`) live on
//  `runtime.swift`. Full INSERT / prune SQL is not ported.
//

import Foundation
import os

let LOG_QUEUE_CAPACITY = 2048
let LOG_BATCH_SIZE = 512
let LOG_FLUSH_INTERVAL: Duration = .seconds(10)
let SQLX_LOG_TARGETS = ["sqlx", "sqlx_core", "sqlx_sqlite"]

/// Filter table matching `log_db::default_filter` (`Targets`).
public struct LogDbTargets: Equatable, Sendable {
    public var defaultLevel: String
    public var targets: [String: String]

    public init(defaultLevel: String, targets: [String: String]) {
        self.defaultLevel = defaultLevel
        self.targets = targets
    }
}

public func defaultFilter() -> LogDbTargets {
    var targets: [String: String] = [
        "h2": "WARN",
        "hyper_util": "WARN",
        "log": "OFF",
        "codex_rmcp_client": "INFO",
        "opentelemetry-otlp": "OFF",
        "opentelemetry-http": "OFF",
        "tonic::transport": "WARN",
        "tower::buffer": "WARN",
        "codex_otel.log_only": "OFF",
        "codex_otel.trace_safe": "OFF",
        "rmcp": "INFO",
        "codex_api::responses_websocket_timing": "OFF",
        "codex_core::post_sampling_token_estimate": "OFF",
        "codex_http_client::transport": "DEBUG",
        "codex_api::sse": "DEBUG",
        "codex_tui::streaming::controller": "DEBUG",
        "codex_tui::streaming::table_holdback": "DEBUG",
    ]
    for target in SQLX_LOG_TARGETS {
        targets["\(target)::"] = "OFF"
    }
    return LogDbTargets(defaultLevel: "TRACE", targets: targets)
}

public struct LogSinkQueueConfig: Equatable, Sendable {
    public var queueCapacity: Int
    public var batchSize: Int
    public var flushInterval: Duration

    public init(
        queueCapacity: Int = 2048,
        batchSize: Int = 512,
        flushInterval: Duration = .seconds(10)
    ) {
        self.queueCapacity = queueCapacity
        self.batchSize = batchSize
        self.flushInterval = flushInterval
    }

    public static let `default` = LogSinkQueueConfig()

    func normalized() -> LogSinkQueueConfig {
        LogSinkQueueConfig(
            queueCapacity: max(queueCapacity, 1),
            batchSize: max(batchSize, 1),
            flushInterval: flushInterval == .zero ? LOG_FLUSH_INTERVAL : flushInterval
        )
    }
}

/// A log writer that can flush entries accepted by its queue.
public protocol LogWriter: Sendable {
    func flush() async
}

/// Receives a formatted, redacted diagnostic when a SQLite log batch is lost.
public protocol LogWriteFailureReporter: Sendable {
    func reportFailure(_ diagnostic: String)
}

public final class LogDbLayer: LogWriter, Sendable {
    private struct LayerState {
        var buffer: [LogEntry] = []
        var writeFailure = false
        var failureReporter: any LogWriteFailureReporter
    }

    private let stateDb: StateRuntime
    private let config: LogSinkQueueConfig
    private let state: OSAllocatedUnfairLock<LayerState>
    public let processUuid: String

    /// Starts the SQLite log writer with a shared, independent failure reporter.
    public static func start(
        stateDb: StateRuntime,
        failureReporter: any LogWriteFailureReporter
    ) -> LogDbLayer {
        startWithConfig(
            stateDb: stateDb,
            failureReporter: failureReporter,
            config: .default
        )
    }

    public static func startWithConfig(
        stateDb: StateRuntime,
        failureReporter: any LogWriteFailureReporter,
        config: LogSinkQueueConfig
    ) -> LogDbLayer {
        LogDbLayer(
            stateDb: stateDb,
            failureReporter: failureReporter,
            config: config.normalized()
        )
    }

    public init(
        stateDb: StateRuntime,
        failureReporter: any LogWriteFailureReporter,
        config: LogSinkQueueConfig = .default
    ) {
        self.stateDb = stateDb
        self.config = config.normalized()
        self.state = OSAllocatedUnfairLock(initialState: LayerState(failureReporter: failureReporter))
        self.processUuid = currentProcessLogUuid()
    }

    /// Replaces the startup reporter once the client notification destination is available.
    public func setFailureReporter(_ reporter: any LogWriteFailureReporter) {
        state.withLock { $0.failureReporter = reporter }
    }

    /// Whether this writer has lost logs, making SQLite incomplete for feedback.
    public func hasWriteFailure() -> Bool {
        state.withLock { $0.writeFailure }
    }

    public func flush() async {
        let entries = takeBuffer()
        guard !entries.isEmpty else { return }
        let started = ContinuousClock.now
        do {
            try await stateDb.insertLogs(entries)
            let duration = ContinuousClock.now - started
            recordLogWrite(telemetry: nil, duration: duration, entries: entries, succeeded: true)
        } catch {
            let duration = ContinuousClock.now - started
            let reporter = state.withLock { current -> any LogWriteFailureReporter in
                current.writeFailure = true
                return current.failureReporter
            }
            let timestamp = stateEncodeRFC3339(Date())
            reporter.reportFailure(
                "\(timestamp) ERROR failed to flush logs to SQLite error=\(error) entries=\(entries.count)\n"
            )
            recordLogWrite(
                telemetry: nil,
                duration: duration,
                entries: entries,
                succeeded: false,
                error: error
            )
        }
    }

    public func trySend(_ entry: LogEntry) {
        let dropped = state.withLock { current -> Bool in
            if current.buffer.count >= config.queueCapacity {
                return true
            }
            current.buffer.append(entry)
            return false
        }
        if dropped {
            recordLogQueueDrop(reason: "full", telemetry: nil)
        }
    }

    private func takeBuffer() -> [LogEntry] {
        state.withLock { current in
            let entries = current.buffer
            current.buffer.removeAll(keepingCapacity: true)
            return entries
        }
    }
}

/// Starts the SQLite log writer with a shared, independent failure reporter.
public func start(
    stateDb: StateRuntime,
    failureReporter: any LogWriteFailureReporter
) -> LogDbLayer {
    LogDbLayer.start(stateDb: stateDb, failureReporter: failureReporter)
}

func currentProcessLogUuid() -> String {
    processLogUuid.withLock { current in
        if let existing = current {
            return existing
        }
        let value = "pid:\(ProcessInfo.processInfo.processIdentifier):\(UUID().uuidString.lowercased())"
        current = value
        return value
    }
}

private let processLogUuid = OSAllocatedUnfairLock<String?>(initialState: nil)

extension StateRuntime {
    public func insertLog(_ entry: LogEntry) async throws {
        try await insertLogs([entry])
    }

    /// Insert a batch of log entries into the logs table.
    public func insertLogs(_ entries: [LogEntry]) async throws {
        if entries.isEmpty {
            return
        }
        _ = LOG_PARTITION_SIZE_LIMIT_BYTES
        _ = LOG_PARTITION_ROW_LIMIT
        throw StateRuntimeError.sqliteUnavailable("logs")
    }

    /// Query logs with optional filters.
    public func queryLogs(_ query: LogQuery) async throws -> [LogRow] {
        _ = query
        throw StateRuntimeError.sqliteUnavailable("logs")
    }

    /// Query feedback logs for a set of threads, capped to the SQLite retention budget.
    public func queryFeedbackLogsForThreads(_ threadIds: [String]) async throws -> [UInt8] {
        if threadIds.isEmpty {
            return []
        }
        _ = LOG_PARTITION_SIZE_LIMIT_BYTES
        throw StateRuntimeError.sqliteUnavailable("logs")
    }

    /// Query per-thread feedback logs, capped to the per-thread SQLite retention budget.
    public func queryFeedbackLogs(_ threadId: String) async throws -> [UInt8] {
        try await queryFeedbackLogsForThreads([threadId])
    }

    /// Return the max log id matching optional filters.
    public func maxLogId(_ query: LogQuery) async throws -> Int64 {
        _ = query
        throw StateRuntimeError.sqliteUnavailable("logs")
    }
}
