//
//  rollout_migration.swift
//  CodexThreadStore
//
//  Port of codex-rs/thread-store/src/local/rollout_migration.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Dry-run inspects JSONL SessionMeta and reports Eligible / AlreadyPaginated
//  / SkippedEmpty / Failed. Apply and pending-journal recovery throw until
//  GRDB projection exists. Canonicalizer / rollback / line-parser helpers
//  live in `rollout_migration/` and are used by tests and a later Apply path.
//

import CodexHistory
import CodexProtocol
import CodexRollout
import Foundation

let PROJECTION_BATCH_BYTES: UInt64 = 256 * 1024
let MAX_ROLLOUT_LINE_BYTES = 16 * 1024 * 1024

enum CanonicalizationAttempt {
    case complete(expectedLength: UInt64, expectedOrdinal: UInt64)
    case needsRollbackPlan
}

enum RolloutMigrationPaths {
    case discover
    case known([String])
}

struct CanonicalizationSource {
    var threadId: ThreadId
    var sourcePath: String
    var stagedPath: String
    var sourcePermissions: [FileAttributeKey: Any]
    var canonicalSessionMeta: RolloutLine
}

/// Controls whether eligible rollouts are reported or migrated.
public enum RolloutMigrationMode: String, Codable, Equatable, Sendable {
    case dryRun = "dry_run"
    case apply
}

/// Selection and throughput limits for a local rollout migration.
public struct RolloutMigrationOptions: Equatable, Sendable {
    public var mode: RolloutMigrationMode
    public var threadIds: [ThreadId]
    public var maxMibPerSecond: UInt64?

    public init(
        mode: RolloutMigrationMode = .dryRun,
        threadIds: [ThreadId] = [],
        maxMibPerSecond: UInt64? = nil
    ) {
        self.mode = mode
        self.threadIds = threadIds
        self.maxMibPerSecond = maxMibPerSecond
    }
}

/// The observable result of inspecting one local rollout.
public enum RolloutMigrationStatus: String, Codable, Equatable, Sendable {
    case eligible
    case migrated
    case alreadyPaginated = "already_paginated"
    case skippedEmpty = "skipped_empty"
    case skippedBusy = "skipped_busy"
    case failed
}

/// A bounded explanation for why one rollout migration failed.
public enum RolloutMigrationFailureReason: String, Codable, Equatable, Sendable {
    case missingSqliteMetadata = "missing_sqlite_metadata"
    case invalidSessionMetadata = "invalid_session_metadata"
    case rolloutReadFailed = "rollout_read_failed"
    case legacyRolloutConversionFailed = "legacy_rollout_conversion_failed"
    case sqliteMaterializationFailed = "sqlite_materialization_failed"
    case rolloutPublishFailed = "rollout_publish_failed"
    case interruptedMigrationRecoveryFailed = "interrupted_migration_recovery_failed"
    case unknown
}

/// The per-thread result of a rollout migration run.
public struct RolloutMigrationOutcome: Codable, Equatable, Sendable {
    public var threadId: ThreadId?
    public var rolloutPath: String
    public var status: RolloutMigrationStatus
    public var failureReason: RolloutMigrationFailureReason?
    public var bytesProcessed: UInt64
    public var message: String?

    enum CodingKeys: String, CodingKey {
        case threadId = "thread_id"
        case rolloutPath = "rollout_path"
        case status
        case failureReason = "failure_reason"
        case bytesProcessed = "bytes_processed"
        case message
    }

    public init(
        threadId: ThreadId?,
        rolloutPath: String,
        status: RolloutMigrationStatus,
        failureReason: RolloutMigrationFailureReason? = nil,
        bytesProcessed: UInt64 = 0,
        message: String? = nil
    ) {
        self.threadId = threadId
        self.rolloutPath = rolloutPath
        self.status = status
        self.failureReason = failureReason
        self.bytesProcessed = bytesProcessed
        self.message = message
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(threadId, forKey: .threadId)
        try container.encode(rolloutPath, forKey: .rolloutPath)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(failureReason, forKey: .failureReason)
        try container.encode(bytesProcessed, forKey: .bytesProcessed)
        try container.encodeIfPresent(message, forKey: .message)
    }
}

/// The complete result of scanning active rollout files.
public struct RolloutMigrationReport: Codable, Equatable, Sendable {
    public var outcomes: [RolloutMigrationOutcome]

    public init(outcomes: [RolloutMigrationOutcome] = []) {
        self.outcomes = outcomes
    }
}

/// Incremental progress emitted while rollout migration scans discovered paths.
public struct RolloutMigrationProgress: Equatable, Sendable {
    public var processedPaths: Int
    public var totalPaths: Int
    public var outcomeStatus: RolloutMigrationStatus?
}

struct RolloutMigrationRateLimiter {
    private var startedAt: Date
    private(set) var bytesProcessed: UInt64
    private var bytesPerSecond: UInt64?
    private var bytesSinceYield: UInt64

    init(maxMibPerSecond: UInt64?) throws {
        if let rate = maxMibPerSecond {
            let bytes = rate.multipliedReportingOverflow(by: 1024 * 1024)
            if bytes.overflow || bytes.partialValue == 0 {
                throw ThreadStoreError.invalidRequest(
                    "--max-mib-per-second must be a positive supported integer")
            }
            bytesPerSecond = bytes.partialValue
        } else {
            bytesPerSecond = nil
        }
        startedAt = Date()
        bytesProcessed = 0
        bytesSinceYield = 0
    }

    mutating func account(_ bytes: UInt64) async {
        bytesProcessed = bytesProcessed &+ bytes
        bytesSinceYield = bytesSinceYield &+ bytes
        if bytesSinceYield < PROJECTION_BATCH_BYTES { return }
        bytesSinceYield = 0
        guard let bytesPerSecond else {
            await Task.yield()
            return
        }
        let expected = Double(bytesProcessed) / Double(bytesPerSecond)
        let elapsed = Date().timeIntervalSince(startedAt)
        if expected > elapsed {
            let remaining = expected - elapsed
            try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
        } else {
            await Task.yield()
        }
    }
}

struct RolloutRecord {
    var line: RolloutLine?
    var byteCount: UInt64
}

enum RolloutMigrationKind {
    case ordinary
    case subagent
}

struct RolloutMigrationFailure: Error {
    var reason: RolloutMigrationFailureReason
    var error: ThreadStoreError
}

func withFailureReason<T>(
    _ result: () throws -> T,
    _ reason: RolloutMigrationFailureReason
) throws -> T {
    do {
        return try result()
    } catch let error as ThreadStoreError {
        throw RolloutMigrationFailure(reason: reason, error: error)
    } catch {
        throw RolloutMigrationFailure(reason: reason, error: migrationError(error))
    }
}

extension LocalThreadStore {
    /// Check whether startup needs to migrate legacy rollouts.
    public func migrateRolloutsOnStartup() async throws {
        try await runMigrateRolloutsOnStartup(store: self)
    }

    /// Inspect or migrate eligible legacy rollout files beneath active and archived sessions.
    public func migrateRollouts(
        _ options: RolloutMigrationOptions
    ) async throws -> RolloutMigrationReport {
        try await migrateRolloutsWithProgressForTrigger(
            options,
            onProgress: { _ in },
            trigger: .manual,
            paths: .discover
        )
    }

    /// Inspect or migrate rollouts while reporting each discovered path after it is processed.
    public func migrateRolloutsWithProgress(
        _ options: RolloutMigrationOptions,
        onProgress: (RolloutMigrationProgress) -> Void
    ) async throws -> RolloutMigrationReport {
        try await migrateRolloutsWithProgressForTrigger(
            options,
            onProgress: onProgress,
            trigger: .manual,
            paths: .discover
        )
    }

    func migrateRolloutsWithProgressForTrigger(
        _ options: RolloutMigrationOptions,
        onProgress: (RolloutMigrationProgress) -> Void,
        trigger: RolloutMigrationTrigger,
        paths: RolloutMigrationPaths
    ) async throws -> RolloutMigrationReport {
        let telemetry = RolloutMigrationTelemetry(trigger: trigger, options: options)
        do {
            let report = try await migrateRolloutsWithProgressInner(
                options, onProgress: onProgress, paths: paths)
            telemetry.finish(.success(report))
            return report
        } catch let error as ThreadStoreError {
            telemetry.finish(.failure(error))
            throw error
        } catch {
            let wrapped = migrationError(error)
            telemetry.finish(.failure(wrapped))
            throw wrapped
        }
    }

    private func migrateRolloutsWithProgressInner(
        _ options: RolloutMigrationOptions,
        onProgress: (RolloutMigrationProgress) -> Void,
        paths: RolloutMigrationPaths
    ) async throws -> RolloutMigrationReport {
        var limiter = try RolloutMigrationRateLimiter(maxMibPerSecond: options.maxMibPerSecond)
        if options.mode == .apply {
            throw ThreadStoreError.unsupported(operation: "rollout_migration")
        }
        var discovered: [String]
        switch paths {
        case .discover:
            discovered = try findAllRolloutPaths(config.codexHome)
        case .known(let known):
            discovered = known
        }
        let totalPaths = discovered.count
        var report = RolloutMigrationReport()
        for (index, path) in discovered.enumerated() {
            let outcome = try await migrateRolloutPath(
                path, options: options, limiter: &limiter)
            report.outcomes.append(contentsOf: outcome.map { [$0] } ?? [])
            onProgress(RolloutMigrationProgress(
                processedPaths: index + 1,
                totalPaths: totalPaths,
                outcomeStatus: outcome?.status
            ))
        }
        return report
    }

    private func migrateRolloutPath(
        _ path: String,
        options: RolloutMigrationOptions,
        limiter: inout RolloutMigrationRateLimiter
    ) async throws -> RolloutMigrationOutcome? {
        var path = path
        var retriedMovedPath = false
        let metadata: SessionMetaLine
        while true {
            do {
                metadata = try readSessionMetaLine(path: path)
                break
            } catch {
                if !retriedMovedPath, isNotFound(error),
                   let current = try findCurrentRolloutPath(config.codexHome, stalePath: path)
                {
                    path = current
                    retriedMovedPath = true
                    continue
                }
                let threadId = threadIdFromRolloutFilename(path)
                if !matchesSelection(options.threadIds, threadId) {
                    return nil
                }
                let empty = fileSize(path) == 0
                return RolloutMigrationOutcome(
                    threadId: threadId,
                    rolloutPath: path,
                    status: empty ? .skippedEmpty : .failed,
                    failureReason: empty
                        ? nil
                        : (isNotFound(error)
                            ? .rolloutReadFailed
                            : .invalidSessionMetadata),
                    bytesProcessed: 0,
                    message: empty ? nil : String(describing: error)
                )
            }
        }
        _ = limiter
        let threadId = metadata.meta.id
        if !matchesSelection(options.threadIds, threadId) {
            return nil
        }
        if metadata.meta.historyMode == .paginated {
            return migrationOutcome(
                threadId: threadId,
                path: path,
                status: .alreadyPaginated,
                bytesProcessed: 0
            )
        }
        return migrationOutcome(
            threadId: threadId,
            path: path,
            status: .eligible,
            bytesProcessed: 0
        )
    }
}

func readRolloutRecord(from handle: FileHandle) throws -> RolloutRecord? {
    var bytes = Data()
    var byteCount = 0
    while byteCount <= MAX_ROLLOUT_LINE_BYTES {
        let chunk: Data
        do {
            chunk = try handle.read(upToCount: 1) ?? Data()
        } catch {
            throw migrationError(error)
        }
        if chunk.isEmpty {
            if bytes.isEmpty { return nil }
            break
        }
        bytes.append(chunk)
        byteCount += 1
        if chunk[0] == UInt8(ascii: "\n") { break }
    }
    if byteCount > MAX_ROLLOUT_LINE_BYTES {
        while true {
            let chunk: Data
            do {
                chunk = try handle.read(upToCount: 1) ?? Data()
            } catch {
                throw migrationError(error)
            }
            if chunk.isEmpty || chunk[0] == UInt8(ascii: "\n") { break }
            byteCount += 1
        }
        return RolloutRecord(line: nil, byteCount: UInt64(byteCount))
    }
    let line: RolloutLine?
    switch parseLegacyRolloutLine(bytes) {
    case .success(let parsed):
        line = parsed
    case .failure:
        line = nil
    }
    return RolloutRecord(line: line, byteCount: UInt64(byteCount))
}

func findRolloutPaths(_ root: String) throws -> [String] {
    var directories = [root]
    var paths: [String] = []
    let fm = FileManager.default
    while let directory = directories.popLast() {
        let entries: [String]
        do {
            entries = try fm.contentsOfDirectory(atPath: directory)
        } catch {
            if isNotFound(error) { continue }
            throw migrationError(error)
        }
        for name in entries {
            let path = (directory as NSString).appendingPathComponent(name)
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: path, isDirectory: &isDirectory) else { continue }
            if isDirectory.boolValue {
                directories.append(path)
                continue
            }
            if name.hasPrefix("rollout-"),
               name.hasSuffix(".jsonl") || name.hasSuffix(".jsonl.zst")
            {
                if name.hasSuffix(".jsonl.zst"),
                   fm.fileExists(atPath: plainRolloutPath(path))
                {
                    continue
                }
                paths.append(path)
            }
        }
    }
    paths.sort(by: >)
    return paths
}

func findAllRolloutPaths(_ codexHome: String) throws -> [String] {
    var paths = try findRolloutPaths(
        (codexHome as NSString).appendingPathComponent(SESSIONS_SUBDIR))
    paths.append(contentsOf: try findRolloutPaths(
        (codexHome as NSString).appendingPathComponent(ARCHIVED_SESSIONS_SUBDIR)))
    return paths
}

func findCurrentRolloutPath(_ codexHome: String, stalePath: String) throws -> String? {
    let fileName = (plainRolloutPath(stalePath) as NSString).lastPathComponent
    guard !fileName.isEmpty else { return nil }
    return try findAllRolloutPaths(codexHome).first { candidate in
        (plainRolloutPath(candidate) as NSString).lastPathComponent == fileName
    }
}

func matchesSelection(_ selected: [ThreadId], _ actual: ThreadId?) -> Bool {
    selected.isEmpty || actual.map { selected.contains($0) } == true
}

func rolloutPathIsCompressed(_ path: String) -> Bool {
    (path as NSString).lastPathComponent.hasSuffix(".jsonl.zst")
}

func threadIdFromRolloutFilename(_ path: String) -> ThreadId? {
    threadIdFromRolloutPath(path)
}

func migrationOutcome(
    threadId: ThreadId,
    path: String,
    status: RolloutMigrationStatus,
    bytesProcessed: UInt64
) -> RolloutMigrationOutcome {
    RolloutMigrationOutcome(
        threadId: threadId,
        rolloutPath: path,
        status: status,
        bytesProcessed: bytesProcessed
    )
}

func skippedBusyOutcome(
    threadId: ThreadId,
    path: String,
    message: String,
    bytesProcessed: UInt64
) -> RolloutMigrationOutcome {
    RolloutMigrationOutcome(
        threadId: threadId,
        rolloutPath: path,
        status: .skippedBusy,
        bytesProcessed: bytesProcessed,
        message: message
    )
}

func migrationError(_ error: Any) -> ThreadStoreError {
    ThreadStoreError.internal("rollout migration failed: \(error)")
}

private func fileSize(_ path: String) -> UInt64 {
    let attributes = try? FileManager.default.attributesOfItem(atPath: path)
    return (attributes?[.size] as? NSNumber)?.uint64Value ?? 0
}

private func isNotFound(_ error: Error) -> Bool {
    let ns = error as NSError
    return ns.domain == NSCocoaErrorDomain && ns.code == NSFileReadNoSuchFileError
        || ns.domain == NSPOSIXErrorDomain && ns.code == ENOENT
}
