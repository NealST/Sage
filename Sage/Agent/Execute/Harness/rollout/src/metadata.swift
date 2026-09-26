//
//  metadata.swift
//  CodexRollout
//
//  Port of codex-rs/rollout/src/metadata.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  `chrono` timestamps map to Foundation `Date`. Item-level
//  `apply_rollout_item` and otel counters wait for CodexState extract /
//  runtime; extract still returns builder + file mtime metadata.
//

import CodexHistory
import CodexProtocol
import CodexState
import CodexUtils
import Foundation

private let backfillBatchSize = 200
private let backfillLeaseSeconds: Int64 = 900
private let filenameTimestampFormat = "yyyy-MM-dd'T'HH-mm-ss"

public struct BackfillStats: Equatable, Sendable {
    public var scanned: Int
    public var upserted: Int
    public var failed: Int

    public init(scanned: Int = 0, upserted: Int = 0, failed: Int = 0) {
        self.scanned = scanned
        self.upserted = upserted
        self.failed = failed
    }
}

/// SQLite backfill operations used by `backfill_sessions`. CodexState runtime
/// will conform once `runtime.rs` is ported.
public protocol RolloutBackfillRuntime: AnyObject {
    func getBackfillState() async throws -> BackfillState
    func tryClaimBackfill(_ leaseSeconds: Int64) async throws -> Bool
    func markBackfillRunning() async throws
    func getThread(_ id: ThreadId) async throws -> ThreadMetadata?
    func upsertThread(_ metadata: ThreadMetadata) async throws
    func setThreadMemoryMode(_ id: ThreadId, _ mode: String) async throws
    func checkpointBackfill(_ watermark: String) async throws
    func markBackfillComplete(_ lastWatermark: String?) async throws
}

func builderFromSessionMeta(
    _ sessionMeta: SessionMetaLine,
    rolloutPath: String
) -> ThreadMetadataBuilder? {
    guard let createdAt = parseTimestampToUtc(sessionMeta.meta.timestamp) else { return nil }
    var builder = ThreadMetadataBuilder(
        id: sessionMeta.meta.id,
        rolloutPath: rolloutPath,
        createdAt: createdAt,
        source: sessionMeta.meta.source
    )
    builder.creatorUserId = sessionMeta.meta.creatorUserId
    builder.creatorAccountId = sessionMeta.meta.creatorAccountId
    builder.historyMode = sessionMeta.meta.historyMode
    builder.originator = sessionMeta.meta.originator.isEmpty ? nil : sessionMeta.meta.originator
    builder.modelProvider = sessionMeta.meta.modelProvider
    builder.agentNickname = sessionMeta.meta.agentNickname
    builder.agentRole = sessionMeta.meta.agentRole
    builder.agentPath = sessionMeta.meta.agentPath
    builder.cwd = sessionMeta.meta.cwd
    builder.cliVersion = sessionMeta.meta.cliVersion
    builder.sandboxPolicy = .newReadOnlyPolicy()
    builder.approvalMode = .onRequest
    if let git = sessionMeta.git {
        builder.gitSha = git.commitHash?.value
        builder.gitBranch = git.branch
        builder.gitOriginUrl = git.repositoryUrl
    }
    return builder
}

public func builderFromItems(_ items: [RolloutItem], rolloutPath: String) -> ThreadMetadataBuilder? {
    if let sessionMeta = items.compactMap({ item -> SessionMetaLine? in
        if case .sessionMeta(let metaLine) = item { return metaLine }
        return nil
    }).first, let builder = builderFromSessionMeta(sessionMeta, rolloutPath: rolloutPath) {
        return builder
    }

    let fileName = (rolloutPath as NSString).lastPathComponent
    guard let parsed = RolloutFileName.parse(fileName) else { return nil }
    return ThreadMetadataBuilder(
        id: parsed.threadId,
        rolloutPath: rolloutPath,
        createdAt: canonicalizeDate(parsed.timestamp),
        source: .default
    )
}

/// Returns the rollout ID encoded in a canonical rollout filename.
public func rolloutIdFromPath(_ rolloutPath: String) -> RolloutId? {
    let fileName = (rolloutPath as NSString).lastPathComponent
    return RolloutFileName.parse(fileName)?.rolloutId
}

/// Reads the logical fork cutoff without mistaking a revert's history base for its parent.
public func forkedFromOrdinalExclusive(
    meta: SessionMeta,
    rolloutPath: String?
) -> UInt64? {
    guard let parentId = meta.forkedFromId else { return nil }
    if let cutoff = meta.forkedFromOrdinalExclusive { return cutoff }
    guard let base = meta.historyBase else { return nil }
    if base.threadId == parentId || rolloutPath.flatMap(rolloutIdFromPath) == meta.id {
        return base.endOrdinalExclusive
    }
    return nil
}

public func extractMetadataFromRollout(
    rolloutPath: String,
    defaultProvider: String
) throws -> ExtractionOutcome {
    let loaded = try RolloutRecorder.loadRolloutItems(path: rolloutPath)
    if loaded.items.isEmpty {
        throw IOError.other("empty session file: \(rolloutPath)")
    }
    guard let builder = builderFromItems(loaded.items, rolloutPath: rolloutPath) else {
        throw IOError.other("rollout missing metadata builder: \(rolloutPath)")
    }
    var metadata = builder.build(defaultProvider: defaultProvider)
    if let updatedAt = fileModifiedTimeUtc(rolloutPath) {
        metadata.updatedAt = updatedAt
        metadata.recencyAt = updatedAt
    }
    let memoryMode = loaded.items.reversed().compactMap { item -> String? in
        if case .sessionMeta(let metaLine) = item { return metaLine.meta.memoryMode }
        return nil
    }.first
    return ExtractionOutcome(
        metadata: metadata,
        memoryMode: memoryMode,
        parseErrors: loaded.parseErrors
    )
}

func backfillSessions(
    runtime: RolloutBackfillRuntime,
    codexHome: String,
    defaultProvider: String
) async {
    await backfillSessionsWithLease(
        runtime: runtime,
        codexHome: codexHome,
        defaultProvider: defaultProvider,
        backfillLeaseSeconds: backfillLeaseSeconds
    )
}

func backfillSessionsWithLease(
    runtime: RolloutBackfillRuntime,
    codexHome: String,
    defaultProvider: String,
    backfillLeaseSeconds: Int64
) async {
    var backfillState: BackfillState
    do {
        backfillState = try await runtime.getBackfillState()
    } catch {
        backfillState = BackfillState()
    }
    if backfillState.status == .complete { return }

    let claimed: Bool
    do {
        claimed = try await runtime.tryClaimBackfill(backfillLeaseSeconds)
    } catch {
        return
    }
    if !claimed { return }

    do {
        backfillState = try await runtime.getBackfillState()
    } catch {
        backfillState = BackfillState(status: .running)
    }
    if backfillState.status != .running {
        do {
            try await runtime.markBackfillRunning()
            backfillState.status = .running
        } catch {}
    }

    let sessionsRoot = (codexHome as NSString).appendingPathComponent(SESSIONS_SUBDIR)
    let archivedRoot = (codexHome as NSString).appendingPathComponent(ARCHIVED_SESSIONS_SUBDIR)
    var rolloutPaths: [BackfillRolloutPath] = []
    for (root, archived) in [(sessionsRoot, false), (archivedRoot, true)] {
        guard FileManager.default.fileExists(atPath: root) else { continue }
        do {
            let paths = try collectRolloutPaths(root)
            rolloutPaths.append(contentsOf: paths.map {
                BackfillRolloutPath(
                    watermark: backfillWatermarkForPath(codexHome: codexHome, path: $0),
                    path: $0,
                    archived: archived
                )
            })
        } catch {}
    }
    rolloutPaths.sort { $0.watermark < $1.watermark }
    if let lastWatermark = backfillState.lastWatermark {
        rolloutPaths.removeAll { $0.watermark <= lastWatermark }
    }

    var stats = BackfillStats()
    var lastWatermark = backfillState.lastWatermark
    for batch in rolloutPaths.chunked(into: backfillBatchSize) {
        for rollout in batch {
            stats.scanned = saturatingAdd(stats.scanned, 1)
            do {
                let outcome = try extractMetadataFromRollout(
                    rolloutPath: rollout.path, defaultProvider: defaultProvider)
                var metadata = outcome.metadata
                metadata.cwd = normalizeCwdForStateDb(metadata.cwd)
                let memoryMode = outcome.memoryMode ?? "enabled"
                let existingMetadata = try? await runtime.getThread(metadata.id)
                let restoreMemoryModeFromRollout = existingMetadata == nil
                    || metadata.historyMode == .legacy
                if let existingMetadata {
                    metadata.preferExistingGitInfo(existingMetadata)
                    metadata.preferExistingExplicitTitle(existingMetadata)
                }
                if rollout.archived && metadata.archivedAt == nil {
                    let fallback = metadata.updatedAt
                    metadata.archivedAt = fileModifiedTimeUtc(rollout.path) ?? fallback
                }
                do {
                    try await runtime.upsertThread(metadata)
                    if restoreMemoryModeFromRollout {
                        do {
                            try await runtime.setThreadMemoryMode(metadata.id, memoryMode)
                        } catch {
                            stats.failed = saturatingAdd(stats.failed, 1)
                            continue
                        }
                    }
                    stats.upserted = saturatingAdd(stats.upserted, 1)
                } catch {
                    stats.failed = saturatingAdd(stats.failed, 1)
                }
            } catch {
                stats.failed = saturatingAdd(stats.failed, 1)
            }
        }
        if let lastEntry = batch.last {
            do {
                try await runtime.checkpointBackfill(lastEntry.watermark)
                lastWatermark = lastEntry.watermark
            } catch {}
        }
    }
    try? await runtime.markBackfillComplete(lastWatermark)
    _ = stats
}

private struct BackfillRolloutPath {
    var watermark: String
    var path: String
    var archived: Bool
}

private func backfillWatermarkForPath(codexHome: String, path: String) -> String {
    let prefix = codexHome.hasSuffix("/") ? codexHome : codexHome + "/"
    let relative = path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
    return relative.replacingOccurrences(of: "\\", with: "/")
}

func fileModifiedTimeUtc(_ path: String) -> Date? {
    let attrs = try? FileManager.default.attributesOfItem(atPath: path)
    return attrs?[.modificationDate] as? Date
}

func parseTimestampToUtc(_ ts: String) -> Date? {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = filenameTimestampFormat
    if let date = formatter.date(from: ts) {
        return canonicalizeDate(date)
    }
    let rfc = ISO8601DateFormatter()
    rfc.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = rfc.date(from: ts) { return date }
    rfc.formatOptions = [.withInternetDateTime]
    return rfc.date(from: ts)
}

func collectRolloutPaths(_ root: String) throws -> [String] {
    var stack = [root]
    var paths: [String] = []
    let fm = FileManager.default
    while let dir = stack.popLast() {
        let entries: [String]
        do {
            entries = try fm.contentsOfDirectory(atPath: dir)
        } catch {
            continue
        }
        for name in entries {
            let path = (dir as NSString).appendingPathComponent(name)
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: path, isDirectory: &isDirectory) else { continue }
            if isDirectory.boolValue {
                stack.append(path)
                continue
            }
            if rolloutFileFromPath(path) != nil {
                paths.append(path)
            }
        }
    }
    return paths
}

func normalizeCwdForStateDb(_ cwd: String) -> String {
    (try? normalizeForPathComparison(cwd)) ?? cwd
}

private func canonicalizeDate(_ date: Date) -> Date {
    Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.towardZero))
}

private func saturatingAdd(_ lhs: Int, _ rhs: Int) -> Int {
    let (result, overflow) = lhs.addingReportingOverflow(rhs)
    return overflow ? Int.max : result
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        var result: [[Element]] = []
        var index = startIndex
        while index < endIndex {
            let next = self.index(index, offsetBy: size, limitedBy: endIndex) ?? endIndex
            result.append(Array(self[index..<next]))
            index = next
        }
        return result
    }
}
