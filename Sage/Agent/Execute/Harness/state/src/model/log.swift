//
//  log.swift
//  CodexState
//
//  Port of codex-rs/state/src/model/log.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  sqlx `FromRow` is omitted; `LogRow` stays a plain record.
//

import Foundation

public struct LogEntry: Codable, Equatable, Sendable {
    public var ts: Int64
    public var tsNanos: Int64
    public var level: String
    public var target: String
    public var message: String?
    public var feedbackLogBody: String?
    public var threadId: String?
    public var processUuid: String?
    public var modulePath: String?
    public var file: String?
    public var line: Int64?

    enum CodingKeys: String, CodingKey {
        case ts
        case tsNanos = "ts_nanos"
        case level, target, message
        case feedbackLogBody = "feedback_log_body"
        case threadId = "thread_id"
        case processUuid = "process_uuid"
        case modulePath = "module_path"
        case file, line
    }

    public init(
        ts: Int64,
        tsNanos: Int64,
        level: String,
        target: String,
        message: String? = nil,
        feedbackLogBody: String? = nil,
        threadId: String? = nil,
        processUuid: String? = nil,
        modulePath: String? = nil,
        file: String? = nil,
        line: Int64? = nil
    ) {
        self.ts = ts
        self.tsNanos = tsNanos
        self.level = level
        self.target = target
        self.message = message
        self.feedbackLogBody = feedbackLogBody
        self.threadId = threadId
        self.processUuid = processUuid
        self.modulePath = modulePath
        self.file = file
        self.line = line
    }

    public func estimatedBytes() -> Int64 {
        let feedback = feedbackLogBody ?? message
        return Int64(feedback?.utf8.count ?? 0)
            + Int64(level.utf8.count)
            + Int64(target.utf8.count)
            + Int64(modulePath?.utf8.count ?? 0)
            + Int64(file?.utf8.count ?? 0)
    }
}

public struct LogRow: Codable, Equatable, Sendable {
    public var id: Int64
    public var ts: Int64
    public var tsNanos: Int64
    public var level: String
    public var target: String
    public var message: String?
    public var threadId: String?
    public var processUuid: String?
    public var file: String?
    public var line: Int64?

    enum CodingKeys: String, CodingKey {
        case id, ts
        case tsNanos = "ts_nanos"
        case level, target, message
        case threadId = "thread_id"
        case processUuid = "process_uuid"
        case file, line
    }

    public init(
        id: Int64,
        ts: Int64,
        tsNanos: Int64,
        level: String,
        target: String,
        message: String? = nil,
        threadId: String? = nil,
        processUuid: String? = nil,
        file: String? = nil,
        line: Int64? = nil
    ) {
        self.id = id
        self.ts = ts
        self.tsNanos = tsNanos
        self.level = level
        self.target = target
        self.message = message
        self.threadId = threadId
        self.processUuid = processUuid
        self.file = file
        self.line = line
    }
}

public struct LogQuery: Codable, Equatable, Sendable {
    public var levelsUpper: [String]
    public var fromTs: Int64?
    public var toTs: Int64?
    public var moduleLike: [String]
    public var fileLike: [String]
    public var threadIds: [String]
    public var search: String?
    public var includeThreadless: Bool
    public var afterId: Int64?
    public var limit: Int?
    public var descending: Bool

    enum CodingKeys: String, CodingKey {
        case levelsUpper = "levels_upper"
        case fromTs = "from_ts"
        case toTs = "to_ts"
        case moduleLike = "module_like"
        case fileLike = "file_like"
        case threadIds = "thread_ids"
        case search
        case includeThreadless = "include_threadless"
        case afterId = "after_id"
        case limit, descending
    }

    public init(
        levelsUpper: [String] = [],
        fromTs: Int64? = nil,
        toTs: Int64? = nil,
        moduleLike: [String] = [],
        fileLike: [String] = [],
        threadIds: [String] = [],
        search: String? = nil,
        includeThreadless: Bool = false,
        afterId: Int64? = nil,
        limit: Int? = nil,
        descending: Bool = false
    ) {
        self.levelsUpper = levelsUpper
        self.fromTs = fromTs
        self.toTs = toTs
        self.moduleLike = moduleLike
        self.fileLike = fileLike
        self.threadIds = threadIds
        self.search = search
        self.includeThreadless = includeThreadless
        self.afterId = afterId
        self.limit = limit
        self.descending = descending
    }
}
