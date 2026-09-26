//
//  list.swift
//  CodexRollout
//
//  Port of codex-rs/rollout/src/list.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Directory walk uses FileManager. Compression-aware discovery accepts
//  `.jsonl` only (`.zst` waits for compression.swift). SQLite lookup is
//  skipped until StateRuntime is ported; filename walk is the fallback.
//  Preview also comes from user `response_item` messages so LocalThreadStore
//  appends are listable (Rust list.rs only reads EventMsg).
//  `EventMsg.threadGoalUpdated` is not in the protocol subset yet.
//

import CodexHistory
import CodexProtocol
import CodexState
import CodexUtils
import Foundation

private let maxScanFiles = 10000
private let headRecordLimit = 10
private let userEventScanLimit = 200
private let userMessageBegin = "## My request for Codex:"
/// Returned page of thread summaries.
public struct ThreadsPage: Equatable, Sendable {
    public var items: [ThreadItem]
    public var nextCursor: Cursor?
    public var numScannedFiles: Int
    public var reachedScanCap: Bool

    public init(
        items: [ThreadItem] = [],
        nextCursor: Cursor? = nil,
        numScannedFiles: Int = 0,
        reachedScanCap: Bool = false
    ) {
        self.items = items
        self.nextCursor = nextCursor
        self.numScannedFiles = numScannedFiles
        self.reachedScanCap = reachedScanCap
    }
}

/// Summary information for a thread rollout file.
public struct ThreadItem: Equatable, Sendable {
    public var originator: String?
    public var path: String
    public var threadId: ThreadId?
    public var firstUserMessage: String?
    public var preview: String?
    public var section: ThreadSection?
    public var projectId: String?
    public var daybreakEnabled: Bool?
    public var cwd: String?
    public var gitBranch: String?
    public var gitSha: String?
    public var gitOriginUrl: SanitizedGitUrl?
    public var source: SessionSource?
    public var historyMode: ThreadHistoryMode
    public var parentThreadId: ThreadId?
    public var agentNickname: String?
    public var agentRole: String?
    public var modelProvider: String?
    public var model: String?
    public var reasoningEffort: ReasoningEffort?
    public var cliVersion: String?
    public var createdAt: String?
    public var updatedAt: String?
    public var recencyAt: String?

    public init(
        originator: String? = nil,
        path: String,
        threadId: ThreadId? = nil,
        firstUserMessage: String? = nil,
        preview: String? = nil,
        section: ThreadSection? = nil,
        projectId: String? = nil,
        daybreakEnabled: Bool? = nil,
        cwd: String? = nil,
        gitBranch: String? = nil,
        gitSha: String? = nil,
        gitOriginUrl: SanitizedGitUrl? = nil,
        source: SessionSource? = nil,
        historyMode: ThreadHistoryMode = .legacy,
        parentThreadId: ThreadId? = nil,
        agentNickname: String? = nil,
        agentRole: String? = nil,
        modelProvider: String? = nil,
        model: String? = nil,
        reasoningEffort: ReasoningEffort? = nil,
        cliVersion: String? = nil,
        createdAt: String? = nil,
        updatedAt: String? = nil,
        recencyAt: String? = nil
    ) {
        self.originator = originator
        self.path = path
        self.threadId = threadId
        self.firstUserMessage = firstUserMessage
        self.preview = preview
        self.section = section
        self.projectId = projectId
        self.daybreakEnabled = daybreakEnabled
        self.cwd = cwd
        self.gitBranch = gitBranch
        self.gitSha = gitSha
        self.gitOriginUrl = gitOriginUrl
        self.source = source
        self.historyMode = historyMode
        self.parentThreadId = parentThreadId
        self.agentNickname = agentNickname
        self.agentRole = agentRole
        self.modelProvider = modelProvider
        self.model = model
        self.reasoningEffort = reasoningEffort
        self.cliVersion = cliVersion
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.recencyAt = recencyAt
    }
}

public typealias ConversationItem = ThreadItem
public typealias ConversationsPage = ThreadsPage

private struct HeadTailSummary {
    var originator: String?
    var sawSessionMeta = false
    var threadId: ThreadId?
    var firstUserMessage: String?
    var preview: String?
    var cwd: String?
    var gitBranch: String?
    var gitSha: String?
    var gitOriginUrl: SanitizedGitUrl?
    var source: SessionSource?
    var historyMode: ThreadHistoryMode = .legacy
    var parentThreadId: ThreadId?
    var agentNickname: String?
    var agentRole: String?
    var modelProvider: String?
    var cliVersion: String?
    var createdAt: String?
    var updatedAt: String?
}

public enum ThreadSortKey: Equatable, Sendable {
    case createdAt
    case updatedAt
    case recencyAt
}

public enum SortDirection: Equatable, Sendable {
    case asc
    case desc
}

public enum ThreadListLayout: Equatable, Sendable {
    case nestedByDate
    case flat
}

public struct ThreadListConfig {
    public var allowedSources: [SessionSource]
    public var modelProviders: [String]?
    public var cwdFilters: [String]?
    public var defaultProvider: String
    public var layout: ThreadListLayout

    public init(
        allowedSources: [SessionSource],
        modelProviders: [String]? = nil,
        cwdFilters: [String]? = nil,
        defaultProvider: String,
        layout: ThreadListLayout
    ) {
        self.allowedSources = allowedSources
        self.modelProviders = modelProviders
        self.cwdFilters = cwdFilters
        self.defaultProvider = defaultProvider
        self.layout = layout
    }
}

/// Pagination cursor identifying the last item in a page.
public struct Cursor: Equatable, Sendable {
    var ts: Date
    var id: ThreadId?

    public init(ts: Date, id: ThreadId? = nil) {
        self.ts = ts
        self.id = id
    }

    static func new(_ ts: Date) -> Cursor { Cursor(ts: ts) }

    static func withThreadId(_ ts: Date, _ id: ThreadId) -> Cursor {
        Cursor(ts: ts, id: id)
    }

    func timestamp() -> Date { ts }
    func threadId() -> ThreadId? { id }
}

extension Cursor: Codable {
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        guard let tsStr = formatRfc3339(ts) else {
            throw EncodingError.invalidValue(
                ts, .init(codingPath: [], debugDescription: "format error"))
        }
        if let id {
            try container.encode("\(tsStr)|\(id)")
        } else {
            try container.encode(tsStr)
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let parsed = parseCursor(string) else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "invalid cursor")
        }
        self = parsed
    }
}

private struct AnchorState {
    var ts: Date
    var passed: Bool

    init(anchor: Cursor?) {
        if let cursor = anchor {
            ts = cursor.ts
            passed = false
        } else {
            ts = Date(timeIntervalSince1970: 0)
            passed = true
        }
    }

    mutating func shouldSkip(ts: Date, id: UUID) -> Bool {
        _ = id
        if passed { return false }
        if ts < self.ts {
            passed = true
            return false
        }
        return true
    }
}

private protocol RolloutFileVisitor {
    mutating func visit(ts: Date, id: UUID, path: String, scanned: Int) -> Bool
}

private struct FilesByCreatedAtVisitor: RolloutFileVisitor {
    var items: [ThreadItem]
    var pageSize: Int
    var anchorState: AnchorState
    var moreMatchesAvailable: Bool
    var allowedSources: [SessionSource]
    var providerMatcher: ProviderMatcher?
    var cwdFilters: [String]?

    mutating func visit(ts: Date, id: UUID, path: String, scanned: Int) -> Bool {
        if scanned >= maxScanFiles && items.count >= pageSize {
            moreMatchesAvailable = true
            return true
        }
        if anchorState.shouldSkip(ts: ts, id: id) { return false }
        if items.count == pageSize {
            moreMatchesAvailable = true
            return true
        }
        let updatedAt = fileModifiedTime(path).flatMap(formatRfc3339)
        if let item = buildThreadItem(
            path: path,
            allowedSources: allowedSources,
            providerMatcher: providerMatcher,
            cwdFilters: cwdFilters,
            updatedAt: updatedAt
        ) {
            items.append(item)
        }
        return false
    }
}

private struct ThreadCandidate {
    var path: String
    var id: UUID
    var updatedAt: Date?
}

private struct FilesByUpdatedAtVisitor: RolloutFileVisitor {
    var candidates: [ThreadCandidate]

    mutating func visit(ts: Date, id: UUID, path: String, scanned: Int) -> Bool {
        _ = ts
        _ = scanned
        candidates.append(
            ThreadCandidate(path: path, id: id, updatedAt: fileModifiedTime(path)))
        return false
    }
}

/// Retrieve recorded thread file paths with token pagination.
public func getThreads(
    codexHome: String,
    pageSize: Int,
    cursor: Cursor?,
    sortKey: ThreadSortKey,
    allowedSources: [SessionSource],
    modelProviders: [String]?,
    cwdFilters: [String]?,
    defaultProvider: String
) throws -> ThreadsPage {
    let root = (codexHome as NSString).appendingPathComponent(SESSIONS_SUBDIR)
    return try getThreadsInRoot(
        root: root,
        pageSize: pageSize,
        cursor: cursor,
        sortKey: sortKey,
        config: ThreadListConfig(
            allowedSources: allowedSources,
            modelProviders: modelProviders,
            cwdFilters: cwdFilters,
            defaultProvider: defaultProvider,
            layout: .nestedByDate
        )
    )
}

public func getThreadsInRoot(
    root: String,
    pageSize: Int,
    cursor: Cursor?,
    sortKey: ThreadSortKey,
    config: ThreadListConfig
) throws -> ThreadsPage {
    guard FileManager.default.fileExists(atPath: root) else {
        return ThreadsPage()
    }
    let providerMatcher = config.modelProviders.flatMap {
        ProviderMatcher(filters: $0, defaultProvider: config.defaultProvider)
    }
    switch config.layout {
    case .nestedByDate:
        return try traverseDirectoriesForPaths(
            root: root,
            pageSize: pageSize,
            anchor: cursor,
            sortKey: sortKey,
            allowedSources: config.allowedSources,
            providerMatcher: providerMatcher,
            cwdFilters: config.cwdFilters
        )
    case .flat:
        return try traverseFlatPaths(
            root: root,
            pageSize: pageSize,
            anchor: cursor,
            sortKey: sortKey,
            allowedSources: config.allowedSources,
            providerMatcher: providerMatcher,
            cwdFilters: config.cwdFilters
        )
    }
}

private func traverseDirectoriesForPaths(
    root: String,
    pageSize: Int,
    anchor: Cursor?,
    sortKey: ThreadSortKey,
    allowedSources: [SessionSource],
    providerMatcher: ProviderMatcher?,
    cwdFilters: [String]?
) throws -> ThreadsPage {
    switch sortKey {
    case .createdAt:
        return try traverseDirectoriesForPathsCreated(
            root: root,
            pageSize: pageSize,
            anchor: anchor,
            allowedSources: allowedSources,
            providerMatcher: providerMatcher,
            cwdFilters: cwdFilters
        )
    case .updatedAt, .recencyAt:
        return try traverseDirectoriesForPathsUpdated(
            root: root,
            pageSize: pageSize,
            anchor: anchor,
            allowedSources: allowedSources,
            providerMatcher: providerMatcher,
            cwdFilters: cwdFilters
        )
    }
}

private func traverseFlatPaths(
    root: String,
    pageSize: Int,
    anchor: Cursor?,
    sortKey: ThreadSortKey,
    allowedSources: [SessionSource],
    providerMatcher: ProviderMatcher?,
    cwdFilters: [String]?
) throws -> ThreadsPage {
    switch sortKey {
    case .createdAt:
        return try traverseFlatPathsCreated(
            root: root,
            pageSize: pageSize,
            anchor: anchor,
            allowedSources: allowedSources,
            providerMatcher: providerMatcher,
            cwdFilters: cwdFilters
        )
    case .updatedAt, .recencyAt:
        return try traverseFlatPathsUpdated(
            root: root,
            pageSize: pageSize,
            anchor: anchor,
            allowedSources: allowedSources,
            providerMatcher: providerMatcher,
            cwdFilters: cwdFilters
        )
    }
}

private func traverseDirectoriesForPathsCreated(
    root: String,
    pageSize: Int,
    anchor: Cursor?,
    allowedSources: [SessionSource],
    providerMatcher: ProviderMatcher?,
    cwdFilters: [String]?
) throws -> ThreadsPage {
    var scannedFiles = 0
    var visitor = FilesByCreatedAtVisitor(
        items: [],
        pageSize: pageSize,
        anchorState: AnchorState(anchor: anchor),
        moreMatchesAvailable: false,
        allowedSources: allowedSources,
        providerMatcher: providerMatcher,
        cwdFilters: cwdFilters
    )
    try walkRolloutFiles(root: root, scannedFiles: &scannedFiles, visitor: &visitor)
    var moreMatchesAvailable = visitor.moreMatchesAvailable
    let reachedScanCap = scannedFiles >= maxScanFiles
    if reachedScanCap && !visitor.items.isEmpty {
        moreMatchesAvailable = true
    }
    let next = moreMatchesAvailable ? buildNextCursor(visitor.items, sortKey: .createdAt) : nil
    return ThreadsPage(
        items: visitor.items,
        nextCursor: next,
        numScannedFiles: scannedFiles,
        reachedScanCap: reachedScanCap
    )
}

private func traverseDirectoriesForPathsUpdated(
    root: String,
    pageSize: Int,
    anchor: Cursor?,
    allowedSources: [SessionSource],
    providerMatcher: ProviderMatcher?,
    cwdFilters: [String]?
) throws -> ThreadsPage {
    var items: [ThreadItem] = []
    var scannedFiles = 0
    var anchorState = AnchorState(anchor: anchor)
    var moreMatchesAvailable = false
    var candidates = try collectFilesByUpdatedAt(root: root, scannedFiles: &scannedFiles)
    candidates.sort { lhs, rhs in
        let tsL = lhs.updatedAt ?? Date(timeIntervalSince1970: 0)
        let tsR = rhs.updatedAt ?? Date(timeIntervalSince1970: 0)
        if tsL != tsR { return tsL > tsR }
        return lhs.id.uuidString > rhs.id.uuidString
    }
    for candidate in candidates {
        let ts = candidate.updatedAt ?? Date(timeIntervalSince1970: 0)
        if anchorState.shouldSkip(ts: ts, id: candidate.id) { continue }
        if items.count == pageSize {
            moreMatchesAvailable = true
            break
        }
        let updatedAtFallback = candidate.updatedAt.flatMap(formatRfc3339)
        if let item = buildThreadItem(
            path: candidate.path,
            allowedSources: allowedSources,
            providerMatcher: providerMatcher,
            cwdFilters: cwdFilters,
            updatedAt: updatedAtFallback
        ) {
            items.append(item)
        }
    }
    let reachedScanCap = scannedFiles >= maxScanFiles
    if reachedScanCap && !items.isEmpty { moreMatchesAvailable = true }
    let next = moreMatchesAvailable ? buildNextCursor(items, sortKey: .updatedAt) : nil
    return ThreadsPage(
        items: items,
        nextCursor: next,
        numScannedFiles: scannedFiles,
        reachedScanCap: reachedScanCap
    )
}

private func traverseFlatPathsCreated(
    root: String,
    pageSize: Int,
    anchor: Cursor?,
    allowedSources: [SessionSource],
    providerMatcher: ProviderMatcher?,
    cwdFilters: [String]?
) throws -> ThreadsPage {
    var items: [ThreadItem] = []
    var scannedFiles = 0
    var anchorState = AnchorState(anchor: anchor)
    var moreMatchesAvailable = false
    let files = try collectFlatRolloutFiles(root: root, scannedFiles: &scannedFiles)
    for (ts, id, path) in files {
        if anchorState.shouldSkip(ts: ts, id: id) { continue }
        if items.count == pageSize {
            moreMatchesAvailable = true
            break
        }
        let updatedAt = fileModifiedTime(path).flatMap(formatRfc3339)
        if let item = buildThreadItem(
            path: path,
            allowedSources: allowedSources,
            providerMatcher: providerMatcher,
            cwdFilters: cwdFilters,
            updatedAt: updatedAt
        ) {
            items.append(item)
        }
    }
    let reachedScanCap = scannedFiles >= maxScanFiles
    if reachedScanCap && !items.isEmpty { moreMatchesAvailable = true }
    let next = moreMatchesAvailable ? buildNextCursor(items, sortKey: .createdAt) : nil
    return ThreadsPage(
        items: items,
        nextCursor: next,
        numScannedFiles: scannedFiles,
        reachedScanCap: reachedScanCap
    )
}

private func traverseFlatPathsUpdated(
    root: String,
    pageSize: Int,
    anchor: Cursor?,
    allowedSources: [SessionSource],
    providerMatcher: ProviderMatcher?,
    cwdFilters: [String]?
) throws -> ThreadsPage {
    var items: [ThreadItem] = []
    var scannedFiles = 0
    var anchorState = AnchorState(anchor: anchor)
    var moreMatchesAvailable = false
    var candidates = try collectFlatFilesByUpdatedAt(root: root, scannedFiles: &scannedFiles)
    candidates.sort { lhs, rhs in
        let tsL = lhs.updatedAt ?? Date(timeIntervalSince1970: 0)
        let tsR = rhs.updatedAt ?? Date(timeIntervalSince1970: 0)
        if tsL != tsR { return tsL > tsR }
        return lhs.id.uuidString > rhs.id.uuidString
    }
    for candidate in candidates {
        let ts = candidate.updatedAt ?? Date(timeIntervalSince1970: 0)
        if anchorState.shouldSkip(ts: ts, id: candidate.id) { continue }
        if items.count == pageSize {
            moreMatchesAvailable = true
            break
        }
        let updatedAtFallback = candidate.updatedAt.flatMap(formatRfc3339)
        if let item = buildThreadItem(
            path: candidate.path,
            allowedSources: allowedSources,
            providerMatcher: providerMatcher,
            cwdFilters: cwdFilters,
            updatedAt: updatedAtFallback
        ) {
            items.append(item)
        }
    }
    let reachedScanCap = scannedFiles >= maxScanFiles
    if reachedScanCap && !items.isEmpty { moreMatchesAvailable = true }
    let next = moreMatchesAvailable ? buildNextCursor(items, sortKey: .updatedAt) : nil
    return ThreadsPage(
        items: items,
        nextCursor: next,
        numScannedFiles: scannedFiles,
        reachedScanCap: reachedScanCap
    )
}

/// Pagination cursor token format: an RFC3339 timestamp with an optional thread ID tie-breaker.
public func parseCursor(_ token: String) -> Cursor? {
    let timestamp: String
    let id: ThreadId?
    if let split = token.range(of: "|", options: .backwards) {
        timestamp = String(token[..<split.lowerBound])
        id = try? ThreadId.fromString(String(token[split.upperBound...]))
        if id == nil { return nil }
    } else {
        timestamp = token
        id = nil
    }
    if let ts = parseRfc3339(timestamp) {
        return Cursor(ts: ts, id: id)
    }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
    guard let ts = formatter.date(from: timestamp) else { return nil }
    return Cursor(ts: ts, id: id)
}

private func buildNextCursor(_ items: [ThreadItem], sortKey: ThreadSortKey) -> Cursor? {
    guard let last = items.last else { return nil }
    let fileName = (last.path as NSString).lastPathComponent
    guard let (createdTs, id) = parseTimestampUuidFromFilename(fileName) else { return nil }
    let ts: Date
    switch sortKey {
    case .createdAt:
        ts = createdTs
    case .updatedAt:
        guard let updatedAt = last.updatedAt, let parsed = parseRfc3339(updatedAt) else { return nil }
        ts = parsed
    case .recencyAt:
        guard let recency = last.recencyAt ?? last.updatedAt, let parsed = parseRfc3339(recency)
        else { return nil }
        ts = parsed
    }
    switch sortKey {
    case .recencyAt:
        guard let threadId = try? ThreadId.fromString(id.uuidString.lowercased()) else { return nil }
        return .withThreadId(ts, threadId)
    case .createdAt, .updatedAt:
        return .new(ts)
    }
}

private func buildThreadItem(
    path: String,
    allowedSources: [SessionSource],
    providerMatcher: ProviderMatcher?,
    cwdFilters: [String]?,
    updatedAt: String?
) -> ThreadItem? {
    let summary = (try? readHeadSummary(path: path, headLimit: headRecordLimit)) ?? HeadTailSummary()
    if !allowedSources.isEmpty {
        guard let source = summary.source, allowedSources.contains(source) else { return nil }
    }
    if let matcher = providerMatcher, !matcher.matches(summary.modelProvider) {
        return nil
    }
    if let cwdFilters {
        guard let cwd = summary.cwd,
              cwdFilters.contains(where: { pathsMatchAfterNormalization(cwd, $0) })
        else { return nil }
    }
    guard summary.sawSessionMeta, summary.preview != nil else { return nil }
    var summaryUpdatedAt = summary.updatedAt
    if summaryUpdatedAt == nil {
        summaryUpdatedAt = updatedAt ?? summary.createdAt
    }
    return ThreadItem(
        originator: summary.originator,
        path: path,
        threadId: summary.threadId,
        firstUserMessage: summary.firstUserMessage,
        preview: summary.preview,
        section: nil,
        projectId: nil,
        daybreakEnabled: nil,
        cwd: summary.cwd,
        gitBranch: summary.gitBranch,
        gitSha: summary.gitSha,
        gitOriginUrl: summary.gitOriginUrl,
        source: summary.source,
        historyMode: summary.historyMode,
        parentThreadId: summary.parentThreadId,
        agentNickname: summary.agentNickname,
        agentRole: summary.agentRole,
        modelProvider: summary.modelProvider,
        model: nil,
        reasoningEffort: nil,
        cliVersion: summary.cliVersion,
        createdAt: summary.createdAt,
        updatedAt: summaryUpdatedAt,
        recencyAt: summaryUpdatedAt
    )
}

public func readThreadItemFromRollout(path: String) -> ThreadItem? {
    buildThreadItem(
        path: path,
        allowedSources: [],
        providerMatcher: nil,
        cwdFilters: nil,
        updatedAt: nil
    )
}

private func collectDirsDesc<T: Comparable>(
    parent: String,
    parse: (String) -> T?
) throws -> [(T, String)] {
    let entries = try FileManager.default.contentsOfDirectory(atPath: parent)
    var vec: [(T, String)] = []
    for name in entries {
        let path = (parent as NSString).appendingPathComponent(name)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              let value = parse(name)
        else { continue }
        vec.append((value, path))
    }
    vec.sort { $0.0 > $1.0 }
    return vec
}

private func collectFlatRolloutFiles(
    root: String,
    scannedFiles: inout Int
) throws -> [(Date, UUID, String)] {
    let entries = try FileManager.default.contentsOfDirectory(atPath: root)
    var collected: [(Date, UUID, String)] = []
    for name in entries {
        if scannedFiles >= maxScanFiles { break }
        let path = (root as NSString).appendingPathComponent(name)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              !isDirectory.boolValue,
              let rollout = rolloutFileFromPath(path),
              let (ts, id) = parseTimestampUuidFromFilename(rollout.plainFileName)
        else { continue }
        scannedFiles += 1
        if scannedFiles > maxScanFiles { break }
        collected.append((ts, id, rollout.path))
    }
    collected.sort { lhs, rhs in
        if lhs.0 != rhs.0 { return lhs.0 > rhs.0 }
        return lhs.1.uuidString > rhs.1.uuidString
    }
    return collected
}

private func collectRolloutDayFiles(_ dayPath: String) throws -> [(Date, UUID, String)] {
    let entries = try FileManager.default.contentsOfDirectory(atPath: dayPath)
    var dayFiles: [(Date, UUID, String)] = []
    for name in entries {
        let path = (dayPath as NSString).appendingPathComponent(name)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              !isDirectory.boolValue,
              let rollout = rolloutFileFromPath(path),
              let (ts, id) = parseTimestampUuidFromFilename(rollout.plainFileName)
        else { continue }
        dayFiles.append((ts, id, rollout.path))
    }
    dayFiles.sort { lhs, rhs in
        if lhs.0 != rhs.0 { return lhs.0 > rhs.0 }
        return lhs.1.uuidString > rhs.1.uuidString
    }
    return dayFiles
}

func parseTimestampUuidFromFilename(_ name: String) -> (Date, UUID)? {
    guard let fileName = RolloutFileName.parse(name),
          let uuid = UUID(uuidString: fileName.threadId.description)
    else { return nil }
    return (fileName.timestamp, uuid)
}

private func collectFilesByUpdatedAt(
    root: String,
    scannedFiles: inout Int
) throws -> [ThreadCandidate] {
    var visitor = FilesByUpdatedAtVisitor(candidates: [])
    try walkRolloutFiles(root: root, scannedFiles: &scannedFiles, visitor: &visitor)
    return visitor.candidates
}

private func collectFlatFilesByUpdatedAt(
    root: String,
    scannedFiles: inout Int
) throws -> [ThreadCandidate] {
    let entries = try FileManager.default.contentsOfDirectory(atPath: root)
    var candidates: [ThreadCandidate] = []
    for name in entries {
        if scannedFiles >= maxScanFiles { break }
        let path = (root as NSString).appendingPathComponent(name)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              !isDirectory.boolValue,
              let rollout = rolloutFileFromPath(path),
              let (_, id) = parseTimestampUuidFromFilename(rollout.plainFileName)
        else { continue }
        scannedFiles += 1
        if scannedFiles > maxScanFiles { break }
        candidates.append(
            ThreadCandidate(
                path: rollout.path, id: id, updatedAt: fileModifiedTime(rollout.path)))
    }
    return candidates
}

private func walkRolloutFiles<V: RolloutFileVisitor>(
    root: String,
    scannedFiles: inout Int,
    visitor: inout V
) throws {
    let yearDirs = try collectDirsDesc(parent: root) { UInt16($0) }
    outer: for (_, yearPath) in yearDirs {
        if scannedFiles >= maxScanFiles { break }
        let monthDirs = try collectDirsDesc(parent: yearPath) { UInt8($0) }
        for (_, monthPath) in monthDirs {
            if scannedFiles >= maxScanFiles { break outer }
            let dayDirs = try collectDirsDesc(parent: monthPath) { UInt8($0) }
            for (_, dayPath) in dayDirs {
                if scannedFiles >= maxScanFiles { break outer }
                let dayFiles = try collectRolloutDayFiles(dayPath)
                for (ts, id, path) in dayFiles {
                    scannedFiles += 1
                    if scannedFiles > maxScanFiles { break outer }
                    if visitor.visit(ts: ts, id: id, path: path, scanned: scannedFiles) {
                        break outer
                    }
                }
            }
        }
    }
}

private struct ProviderMatcher {
    var filters: [String]
    var matchesDefaultProvider: Bool

    init?(filters: [String], defaultProvider: String) {
        if filters.isEmpty { return nil }
        self.filters = filters
        matchesDefaultProvider = filters.contains(defaultProvider)
    }

    func matches(_ sessionProvider: String?) -> Bool {
        if let provider = sessionProvider {
            return filters.contains(provider)
        }
        return matchesDefaultProvider
    }
}

private func readHeadSummary(path: String, headLimit: Int) throws -> HeadTailSummary {
    let lines = try openRolloutLines(path)
    var summary = HeadTailSummary()
    var linesScanned = 0
    for line in lines {
        if linesScanned >= headLimit
            && !(summary.sawSessionMeta
                && (summary.preview == nil || summary.firstUserMessage == nil)
                && linesScanned < headLimit + userEventScanLimit)
        {
            break
        }
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { continue }
        linesScanned += 1
        let rolloutLine: RolloutLine
        do {
            rolloutLine = try parseRolloutLine(trimmed)
        } catch {
            if !summary.sawSessionMeta,
               let value = try? JSONDecoder().decode(JSONValue.self, from: Data(trimmed.utf8))
            {
                try rejectUnknownThreadHistoryMode(value)
            }
            continue
        }
        switch rolloutLine.item {
        case .sessionMeta(let sessionMetaLine):
            if !summary.sawSessionMeta {
                summary.originator = sessionMetaLine.meta.originator.isEmpty
                    ? nil : sessionMetaLine.meta.originator
                summary.source = sessionMetaLine.meta.source
                summary.historyMode = sessionMetaLine.meta.historyMode
                summary.parentThreadId = sessionMetaLine.meta.parentThreadId
                summary.agentNickname = sessionMetaLine.meta.agentNickname
                summary.agentRole = sessionMetaLine.meta.agentRole
                summary.modelProvider = sessionMetaLine.meta.modelProvider
                summary.threadId = sessionMetaLine.meta.id
                summary.cwd = sessionMetaLine.meta.cwd
                summary.gitBranch = sessionMetaLine.git?.branch
                summary.gitSha = sessionMetaLine.git?.commitHash?.value
                summary.gitOriginUrl = sessionMetaLine.git?.repositoryUrl
                summary.cliVersion = sessionMetaLine.meta.cliVersion
                summary.createdAt = sessionMetaLine.meta.timestamp
                summary.sawSessionMeta = true
                if CodexState.isGuardianReviewSource(sessionMetaLine.meta.source) {
                    summary.preview = GUARDIAN_THREAD_PREVIEW
                    return summary
                }
            }
        case .responseItem(let envelope):
            if summary.createdAt == nil { summary.createdAt = rolloutLine.timestamp }
            if let preview = responseItemUserPreview(envelope) {
                if summary.preview == nil { summary.preview = preview }
                if summary.firstUserMessage == nil { summary.firstUserMessage = preview }
            }
        case .interAgentCommunication:
            if summary.createdAt == nil { summary.createdAt = rolloutLine.timestamp }
        case .eventMsg(let event):
            if let preview = eventMsgPreview(event) {
                let isUserMessage: Bool
                switch event {
                case .userMessage:
                    isUserMessage = true
                case .itemCompleted(let completed):
                    if case .userMessage = completed.item { isUserMessage = true }
                    else { isUserMessage = false }
                default:
                    isUserMessage = false
                }
                if summary.preview == nil { summary.preview = preview }
                if isUserMessage && summary.firstUserMessage == nil {
                    summary.firstUserMessage = preview
                }
            }
        default:
            break
        }
        if summary.sawSessionMeta && summary.preview != nil && summary.firstUserMessage != nil {
            break
        }
    }
    return summary
}

/// Read up to `HEAD_RECORD_LIMIT` records from the start of the rollout file.
public func readHeadForSummary(path: String) throws -> [JSONValue] {
    let lines = try openRolloutLines(path)
    var head: [JSONValue] = []
    for line in lines {
        if head.count >= headRecordLimit { break }
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { continue }
        guard let rolloutLine = try? parseRolloutLine(trimmed) else { continue }
        switch rolloutLine.item {
        case .sessionMeta(let sessionMetaLine):
            if let value = encodeJSON(sessionMetaLine) { head.append(value) }
        case .responseItem(let envelope):
            if let value = encodeJSON(envelope.item) { head.append(value) }
        case .interAgentCommunication(let communication):
            if let value = encodeJSON(communication) { head.append(value) }
        default:
            break
        }
    }
    return head
}

private func responseItemUserPreview(_ envelope: ResponseItemEnvelope) -> String? {
    guard case .message(_, let role, let content, _, _) = envelope.item,
          role == "user"
    else { return nil }
    let text = content.compactMap { item -> String? in
        switch item {
        case .inputText(let text), .outputText(let text):
            return text
        default:
            return nil
        }
    }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    return text.isEmpty ? nil : text
}

private func eventMsgPreview(_ event: EventMsg) -> String? {
    switch event {
    case .userMessage(let user):
        return userMessagePreview(user)
    case .itemCompleted(let completed):
        if case .userMessage(let user) = completed.item {
            return userMessagePreview(user.asLegacyUserMessageEvent())
        }
        return nil
    default:
        return nil
    }
}

public struct MetadataReadError: Error, CustomStringConvertible {
    public var reason: String
    public var error: any Error

    public var description: String { String(describing: error) }
}

/// Read the SessionMetaLine from the head of a rollout file.
public func readSessionMetaLine(path: String) throws -> SessionMetaLine {
    let lines = try openRolloutLines(path)
    for line in lines {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { continue }
        if let rolloutLine = try? parseRolloutLine(trimmed) {
            switch rolloutLine.item {
            case .sessionMeta(let sessionMetaLine):
                return sessionMetaLine
            case .responseItem, .interAgentCommunication:
                throw IOError.other(
                    MetadataReadError(
                        reason: "response_before_metadata",
                        error: IOError.other(
                            "rollout at \(path) does not start with session metadata"
                        )
                    ).description
                )
            default:
                continue
            }
        } else if let value = try? JSONDecoder().decode(JSONValue.self, from: Data(trimmed.utf8)) {
            do {
                try rejectUnknownThreadHistoryMode(value)
            } catch {
                throw IOError.other(
                    MetadataReadError(reason: "invalid_history_mode", error: error).description)
            }
        }
    }
    throw IOError.other(
        MetadataReadError(
            reason: "missing_metadata",
            error: IOError.other("rollout at \(path) is empty")
        ).description
    )
}

private func fileModifiedTime(_ path: String) -> Date? {
    fileModifiedTimeUtc(path).map(truncateToMillis)
}

private func truncateToMillis(_ date: Date) -> Date {
    let millis = (date.timeIntervalSince1970 * 1000).rounded(.towardZero) / 1000
    return Date(timeIntervalSince1970: millis)
}

func formatRfc3339(_ date: Date) -> String? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
}

func parseRfc3339(_ token: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: token) { return date }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: token)
}

/// Locate the newest rollout file owned by a thread ID.
public func findThreadPathByIdStr(
    codexHome: String,
    idStr: String,
    stateDbCtx: Any? = nil
) throws -> String? {
    try findThreadPathByIdStrInSubdir(
        codexHome: codexHome,
        subdir: SESSIONS_SUBDIR,
        idStr: idStr,
        stateDbCtx: stateDbCtx
    )
}

/// Locate the newest archived rollout file owned by a thread ID.
public func findArchivedThreadPathByIdStr(
    codexHome: String,
    idStr: String,
    stateDbCtx: Any? = nil
) throws -> String? {
    try findThreadPathByIdStrInSubdir(
        codexHome: codexHome,
        subdir: ARCHIVED_SESSIONS_SUBDIR,
        idStr: idStr,
        stateDbCtx: stateDbCtx
    )
}

/// Locate one immutable rollout file by its rollout ID across unarchived and archived storage.
public func findRolloutPathByRolloutId(codexHome: String, rolloutId: RolloutId) throws -> String? {
    for subdir in [SESSIONS_SUBDIR, ARCHIVED_SESSIONS_SUBDIR] {
        let root = (codexHome as NSString).appendingPathComponent(subdir)
        if let path = try findRolloutPathByRolloutIdFromFilenames(root: root, rolloutId: rolloutId) {
            return path
        }
    }
    return nil
}

/// Extract the `YYYY/MM/DD` directory components from a rollout filename.
public func rolloutDateParts(_ fileName: String) -> (String, String, String)? {
    guard let date = fileName.dropPrefix("rollout-")?.prefix(10), date.count == 10 else {
        return nil
    }
    let year = String(date.prefix(4))
    let month = String(date.dropFirst(5).prefix(2))
    let day = String(date.dropFirst(8).prefix(2))
    return (year, month, day)
}

private func findThreadPathByIdStrInSubdir(
    codexHome: String,
    subdir: String,
    idStr: String,
    stateDbCtx: Any?
) throws -> String? {
    _ = stateDbCtx
    guard UUID(uuidString: idStr) != nil else { return nil }
    let root = (codexHome as NSString).appendingPathComponent(subdir)
    guard FileManager.default.fileExists(atPath: root) else { return nil }
    if let path = try findThreadPathByIdFromFilenames(root: root, idStr: idStr) {
        return path
    }
    return try findThreadPathByFilenameContains(root: root, idStr: idStr)
}

private func findThreadPathByIdFromFilenames(root: String, idStr: String) throws -> String? {
    guard let target = try? ThreadId.fromString(idStr) else { return nil }
    var newest: (Date, UUID, String)?
    try visitRolloutFilenames(root: root) { fileName, path in
        if fileName.threadId != target { return false }
        guard let rolloutId = UUID(uuidString: fileName.rolloutId.description) else { return false }
        let candidate = (fileName.timestamp, rolloutId, path)
        if newest == nil
            || candidate.0 > newest!.0
            || (candidate.0 == newest!.0 && candidate.1.uuidString > newest!.1.uuidString)
        {
            newest = candidate
        }
        return false
    }
    return newest?.2
}

private func findRolloutPathByRolloutIdFromFilenames(
    root: String,
    rolloutId: RolloutId
) throws -> String? {
    var found: String?
    try visitRolloutFilenames(root: root) { fileName, path in
        if fileName.rolloutId == rolloutId {
            found = path
            return true
        }
        return false
    }
    return found
}

private func findThreadPathByFilenameContains(root: String, idStr: String) throws -> String? {
    var found: String?
    try visitRolloutFilenames(root: root) { fileName, path in
        if fileName.threadId.description == idStr || fileName.rolloutId.description == idStr {
            found = path
            return true
        }
        return false
    }
    return found
}

private func visitRolloutFilenames(
    root: String,
    visitor: (RolloutFileName, String) -> Bool
) throws {
    var stack = [root]
    let fm = FileManager.default
    while let dir = stack.popLast() {
        let entries: [String]
        do {
            entries = try fm.contentsOfDirectory(atPath: dir)
        } catch let error as NSError
            where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError
        {
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
            guard let rollout = rolloutFileFromPath(path),
                  let fileName = RolloutFileName.parse(rollout.plainFileName)
            else { continue }
            if visitor(fileName, rollout.path) { return }
        }
    }
}

func rolloutFileFromPath(_ path: String) -> (path: String, plainFileName: String)? {
    let name = (path as NSString).lastPathComponent
    if name.hasSuffix(".zst") { return nil }
    guard let plain = parseRolloutFileName(name) else { return nil }
    return (path, plain)
}

func openRolloutLines(_ path: String) throws -> [String] {
    let text = try String(contentsOfFile: path, encoding: .utf8)
    return text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
}

func userMessagePreview(_ user: UserMessageEvent) -> String? {
    let message = stripUserMessagePrefix(user.message)
    if !message.isEmpty { return message }
    if (user.images?.isEmpty == false) || (user.fileIds?.isEmpty == false)
        || !user.localImages.isEmpty
    {
        return "[Image]"
    }
    if (user.audio?.isEmpty == false) || !user.localAudio.isEmpty {
        return "[Audio]"
    }
    return nil
}

func stripUserMessagePrefix(_ text: String) -> String {
    if let range = text.range(of: userMessageBegin) {
        return String(text[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return text.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func encodeJSON<T: Encodable>(_ value: T) -> JSONValue? {
    guard let data = try? JSONEncoder().encode(value) else { return nil }
    return try? JSONDecoder().decode(JSONValue.self, from: data)
}

private extension String {
    func dropPrefix(_ prefix: String) -> String? {
        guard hasPrefix(prefix) else { return nil }
        return String(dropFirst(prefix.count))
    }
}
