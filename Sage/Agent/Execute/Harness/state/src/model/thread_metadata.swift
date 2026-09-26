//
//  thread_metadata.swift
//  CodexState
//
//  Port of codex-rs/state/src/model/thread_metadata.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  sqlx row mapping is omitted. `PathBuf` maps to `String`.
//  `DateTime<Utc>` maps to `Date` with RFC3339 Codable.
//

import CodexProtocol
import Foundation

/// The sort key to use when listing threads.
public enum SortKey: String, Codable, Equatable, Sendable {
    /// Sort by the thread's creation timestamp.
    case createdAt
    /// Sort by the thread's last update timestamp.
    case updatedAt
    /// Sort by the thread's product recency timestamp.
    case recencyAt
    /// Sort by the thread's stable position within its user-selected section.
    case sectionPosition
}

/// Sort direction to use when listing threads.
public enum SortDirection: String, Codable, Equatable, Sendable {
    case asc
    case desc
}

/// Spawn-graph relationship used to filter thread listings.
public enum ThreadRelationFilter: Codable, Equatable, Sendable {
    /// Return only threads whose immediate parent is the given thread.
    case directChildrenOf(ThreadId)
    /// Return every thread transitively descended from the given thread.
    case descendantsOf(ThreadId)
}

/// A pagination anchor used for keyset pagination.
public struct Anchor: Codable, Equatable, Sendable {
    /// The timestamp component of the anchor.
    public var ts: Date
    /// The thread ID component used to disambiguate equal recency timestamps.
    public var id: ThreadId?

    public init(ts: Date, id: ThreadId? = nil) {
        self.ts = ts
        self.id = id
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ts = try stateDecodeRFC3339(try container.decode(String.self, forKey: .ts))
        id = try container.decodeIfPresent(ThreadId.self, forKey: .id)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(stateEncodeRFC3339(ts), forKey: .ts)
        try container.encodeIfPresent(id, forKey: .id)
    }

    private enum CodingKeys: String, CodingKey {
        case ts, id
    }
}

/// Visual presentation metadata owned by a thread section.
public struct ThreadSectionAppearance: Codable, Equatable, Sendable {
    public var icon: String?
    public var color: String?

    public init(icon: String? = nil, color: String? = nil) {
        self.icon = icon
        self.color = color
    }
}

/// An independently persisted thread section and its user-facing presentation.
public struct ThreadSection: Codable, Equatable, Sendable {
    /// Opaque UUIDv7 identifying the section independently of its name.
    public var id: String
    /// User-facing section name.
    public var name: String
    public var appearance: ThreadSectionAppearance?

    public init(id: String, name: String, appearance: ThreadSectionAppearance? = nil) {
        self.id = id
        self.name = name
        self.appearance = appearance
    }

    public init(id: String, name: String, appearanceJSON: String?) throws {
        self.id = id
        self.name = name
        if let appearanceJSON {
            guard let data = appearanceJSON.data(using: .utf8) else {
                throw StateModelError("invalid section appearance JSON")
            }
            self.appearance = try JSONDecoder().decode(ThreadSectionAppearance.self, from: data)
        } else {
            self.appearance = nil
        }
    }
}

/// A cursor-paginated page of independently persisted thread sections.
public struct ThreadSectionsPage: Codable, Equatable, Sendable {
    /// Sections in ascending identifier order.
    public var sections: [ThreadSection]
    /// Identifier after which the next page starts, if any.
    public var nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case sections
        case nextCursor = "next_cursor"
    }

    public init(sections: [ThreadSection], nextCursor: String? = nil) {
        self.sections = sections
        self.nextCursor = nextCursor
    }
}

/// A single page of thread metadata results.
public struct ThreadsPage: Codable, Equatable, Sendable {
    /// The thread metadata items in this page.
    public var items: [ThreadMetadata]
    /// Immediate parents for page items found through the persisted spawn graph.
    public var parentThreadIds: [ThreadId: ThreadId]
    /// The next anchor to use for pagination, if any.
    public var nextAnchor: Anchor?
    /// The number of rows scanned to produce this page.
    public var numScannedRows: Int

    enum CodingKeys: String, CodingKey {
        case items
        case parentThreadIds = "parent_thread_ids"
        case nextAnchor = "next_anchor"
        case numScannedRows = "num_scanned_rows"
    }

    public init(
        items: [ThreadMetadata],
        parentThreadIds: [ThreadId: ThreadId] = [:],
        nextAnchor: Anchor? = nil,
        numScannedRows: Int
    ) {
        self.items = items
        self.parentThreadIds = parentThreadIds
        self.nextAnchor = nextAnchor
        self.numScannedRows = numScannedRows
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decode([ThreadMetadata].self, forKey: .items)
        let rawParents = try container.decodeIfPresent([String: String].self, forKey: .parentThreadIds) ?? [:]
        var mapped: [ThreadId: ThreadId] = [:]
        for (key, value) in rawParents {
            mapped[try ThreadId.fromString(key)] = try ThreadId.fromString(value)
        }
        parentThreadIds = mapped
        nextAnchor = try container.decodeIfPresent(Anchor.self, forKey: .nextAnchor)
        numScannedRows = try container.decode(Int.self, forKey: .numScannedRows)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(items, forKey: .items)
        var rawParents: [String: String] = [:]
        for (key, value) in parentThreadIds {
            rawParents[key.description] = value.description
        }
        try container.encode(rawParents, forKey: .parentThreadIds)
        try container.encodeIfPresent(nextAnchor, forKey: .nextAnchor)
        try container.encode(numScannedRows, forKey: .numScannedRows)
    }
}

/// The outcome of extracting metadata from a rollout.
public struct ExtractionOutcome: Codable, Equatable, Sendable {
    /// The extracted thread metadata.
    public var metadata: ThreadMetadata
    /// The explicit thread memory mode from rollout metadata, if present.
    public var memoryMode: String?
    /// The number of rollout lines that failed to parse.
    public var parseErrors: Int

    enum CodingKeys: String, CodingKey {
        case metadata
        case memoryMode = "memory_mode"
        case parseErrors = "parse_errors"
    }

    public init(metadata: ThreadMetadata, memoryMode: String? = nil, parseErrors: Int) {
        self.metadata = metadata
        self.memoryMode = memoryMode
        self.parseErrors = parseErrors
    }
}

/// Canonical persisted thread metadata.
public struct ThreadMetadata: Codable, Equatable, Sendable {
    /// Originator recorded at creation, if available.
    public var originator: String?
    /// ChatGPT user that created the thread, if known.
    public var creatorUserId: String?
    /// ChatGPT account at creation, if known.
    public var creatorAccountId: String?
    /// The thread identifier.
    public var id: ThreadId
    /// The absolute rollout path on disk.
    public var rolloutPath: String
    /// The creation timestamp.
    public var createdAt: Date
    /// The last update timestamp.
    public var updatedAt: Date
    /// The product recency timestamp.
    public var recencyAt: Date
    /// The session source (stringified enum).
    public var source: String
    /// Persisted thread history contract selected when this thread was created.
    public var historyMode: ThreadHistoryMode
    /// Optional analytics source classification for this thread.
    public var threadSource: ThreadSource?
    /// Optional random unique nickname assigned to an AgentControl-spawned sub-agent.
    public var agentNickname: String?
    /// Optional role (agent_role) assigned to an AgentControl-spawned sub-agent.
    public var agentRole: String?
    /// Optional canonical agent path assigned to an AgentControl-spawned sub-agent.
    public var agentPath: String?
    /// The model provider identifier.
    public var modelProvider: String
    /// The latest observed model for the thread.
    public var model: String?
    /// The latest observed reasoning effort for the thread.
    public var reasoningEffort: ReasoningEffort?
    /// The working directory for the thread.
    public var cwd: String
    /// Version of the CLI that created the thread.
    public var cliVersion: String
    /// A best-effort thread title.
    public var title: String
    /// Explicit user-facing thread name, if one was set.
    public var name: String?
    /// Best available user-facing preview for discovery and list display.
    public var preview: String?
    /// The sandbox policy (stringified enum).
    public var sandboxPolicy: String
    /// The approval mode (stringified enum).
    public var approvalMode: String
    /// The last observed token usage.
    public var tokensUsed: Int64
    /// First user message observed for this thread, if any.
    public var firstUserMessage: String?
    /// The archive timestamp, if the thread is archived.
    public var archivedAt: Date?
    /// The user-selected section for this thread, if any.
    public var section: ThreadSection?
    /// The stable sparse ordering rank within the user-selected section.
    public var sectionPosition: Int64?
    /// The time when the thread most recently entered its current section.
    public var sectionEnteredAt: Date?
    /// Canonical project assignment owned by app-server, if any.
    public var projectId: String?
    /// User-selected Daybreak preference, absent until explicitly set.
    public var daybreakEnabled: Bool?
    /// The git commit SHA, if known.
    public var gitSha: String?
    /// The git branch name, if known.
    public var gitBranch: String?
    /// The git origin URL, if known.
    public var gitOriginUrl: SanitizedGitUrl?

    enum CodingKeys: String, CodingKey {
        case originator
        case creatorUserId = "creator_user_id"
        case creatorAccountId = "creator_account_id"
        case id
        case rolloutPath = "rollout_path"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case recencyAt = "recency_at"
        case source
        case historyMode = "history_mode"
        case threadSource = "thread_source"
        case agentNickname = "agent_nickname"
        case agentRole = "agent_role"
        case agentPath = "agent_path"
        case modelProvider = "model_provider"
        case model
        case reasoningEffort = "reasoning_effort"
        case cwd
        case cliVersion = "cli_version"
        case title, name, preview
        case sandboxPolicy = "sandbox_policy"
        case approvalMode = "approval_mode"
        case tokensUsed = "tokens_used"
        case firstUserMessage = "first_user_message"
        case archivedAt = "archived_at"
        case section
        case sectionPosition = "section_position"
        case sectionEnteredAt = "section_entered_at"
        case projectId = "project_id"
        case daybreakEnabled = "daybreak_enabled"
        case gitSha = "git_sha"
        case gitBranch = "git_branch"
        case gitOriginUrl = "git_origin_url"
    }

    public init(
        originator: String? = nil,
        creatorUserId: String? = nil,
        creatorAccountId: String? = nil,
        id: ThreadId,
        rolloutPath: String,
        createdAt: Date,
        updatedAt: Date,
        recencyAt: Date,
        source: String,
        historyMode: ThreadHistoryMode,
        threadSource: ThreadSource? = nil,
        agentNickname: String? = nil,
        agentRole: String? = nil,
        agentPath: String? = nil,
        modelProvider: String,
        model: String? = nil,
        reasoningEffort: ReasoningEffort? = nil,
        cwd: String,
        cliVersion: String,
        title: String,
        name: String? = nil,
        preview: String? = nil,
        sandboxPolicy: String,
        approvalMode: String,
        tokensUsed: Int64,
        firstUserMessage: String? = nil,
        archivedAt: Date? = nil,
        section: ThreadSection? = nil,
        sectionPosition: Int64? = nil,
        sectionEnteredAt: Date? = nil,
        projectId: String? = nil,
        daybreakEnabled: Bool? = nil,
        gitSha: String? = nil,
        gitBranch: String? = nil,
        gitOriginUrl: SanitizedGitUrl? = nil
    ) {
        self.originator = originator
        self.creatorUserId = creatorUserId
        self.creatorAccountId = creatorAccountId
        self.id = id
        self.rolloutPath = rolloutPath
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.recencyAt = recencyAt
        self.source = source
        self.historyMode = historyMode
        self.threadSource = threadSource
        self.agentNickname = agentNickname
        self.agentRole = agentRole
        self.agentPath = agentPath
        self.modelProvider = modelProvider
        self.model = model
        self.reasoningEffort = reasoningEffort
        self.cwd = cwd
        self.cliVersion = cliVersion
        self.title = title
        self.name = name
        self.preview = preview
        self.sandboxPolicy = sandboxPolicy
        self.approvalMode = approvalMode
        self.tokensUsed = tokensUsed
        self.firstUserMessage = firstUserMessage
        self.archivedAt = archivedAt
        self.section = section
        self.sectionPosition = sectionPosition
        self.sectionEnteredAt = sectionEnteredAt
        self.projectId = projectId
        self.daybreakEnabled = daybreakEnabled
        self.gitSha = gitSha
        self.gitBranch = gitBranch
        self.gitOriginUrl = gitOriginUrl
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        originator = try container.decodeIfPresent(String.self, forKey: .originator)
        creatorUserId = try container.decodeIfPresent(String.self, forKey: .creatorUserId)
        creatorAccountId = try container.decodeIfPresent(String.self, forKey: .creatorAccountId)
        id = try container.decode(ThreadId.self, forKey: .id)
        rolloutPath = try container.decode(String.self, forKey: .rolloutPath)
        createdAt = try stateDecodeRFC3339(try container.decode(String.self, forKey: .createdAt))
        updatedAt = try stateDecodeRFC3339(try container.decode(String.self, forKey: .updatedAt))
        recencyAt = try stateDecodeRFC3339(try container.decode(String.self, forKey: .recencyAt))
        source = try container.decode(String.self, forKey: .source)
        historyMode = try container.decode(ThreadHistoryMode.self, forKey: .historyMode)
        threadSource = try container.decodeIfPresent(ThreadSource.self, forKey: .threadSource)
        agentNickname = try container.decodeIfPresent(String.self, forKey: .agentNickname)
        agentRole = try container.decodeIfPresent(String.self, forKey: .agentRole)
        agentPath = try container.decodeIfPresent(String.self, forKey: .agentPath)
        modelProvider = try container.decode(String.self, forKey: .modelProvider)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        reasoningEffort = try container.decodeIfPresent(ReasoningEffort.self, forKey: .reasoningEffort)
        cwd = try container.decode(String.self, forKey: .cwd)
        cliVersion = try container.decode(String.self, forKey: .cliVersion)
        title = try container.decode(String.self, forKey: .title)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        preview = try container.decodeIfPresent(String.self, forKey: .preview)
        sandboxPolicy = try container.decode(String.self, forKey: .sandboxPolicy)
        approvalMode = try container.decode(String.self, forKey: .approvalMode)
        tokensUsed = try container.decode(Int64.self, forKey: .tokensUsed)
        firstUserMessage = try container.decodeIfPresent(String.self, forKey: .firstUserMessage)
        if let raw = try container.decodeIfPresent(String.self, forKey: .archivedAt) {
            archivedAt = try stateDecodeRFC3339(raw)
        } else {
            archivedAt = nil
        }
        section = try container.decodeIfPresent(ThreadSection.self, forKey: .section)
        sectionPosition = try container.decodeIfPresent(Int64.self, forKey: .sectionPosition)
        if let raw = try container.decodeIfPresent(String.self, forKey: .sectionEnteredAt) {
            sectionEnteredAt = try stateDecodeRFC3339(raw)
        } else {
            sectionEnteredAt = nil
        }
        projectId = try container.decodeIfPresent(String.self, forKey: .projectId)
        daybreakEnabled = try container.decodeIfPresent(Bool.self, forKey: .daybreakEnabled)
        gitSha = try container.decodeIfPresent(String.self, forKey: .gitSha)
        gitBranch = try container.decodeIfPresent(String.self, forKey: .gitBranch)
        gitOriginUrl = try container.decodeIfPresent(SanitizedGitUrl.self, forKey: .gitOriginUrl)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(originator, forKey: .originator)
        try container.encodeIfPresent(creatorUserId, forKey: .creatorUserId)
        try container.encodeIfPresent(creatorAccountId, forKey: .creatorAccountId)
        try container.encode(id, forKey: .id)
        try container.encode(rolloutPath, forKey: .rolloutPath)
        try container.encode(stateEncodeRFC3339(createdAt), forKey: .createdAt)
        try container.encode(stateEncodeRFC3339(updatedAt), forKey: .updatedAt)
        try container.encode(stateEncodeRFC3339(recencyAt), forKey: .recencyAt)
        try container.encode(source, forKey: .source)
        try container.encode(historyMode, forKey: .historyMode)
        try container.encodeIfPresent(threadSource, forKey: .threadSource)
        try container.encodeIfPresent(agentNickname, forKey: .agentNickname)
        try container.encodeIfPresent(agentRole, forKey: .agentRole)
        try container.encodeIfPresent(agentPath, forKey: .agentPath)
        try container.encode(modelProvider, forKey: .modelProvider)
        try container.encodeIfPresent(model, forKey: .model)
        try container.encodeIfPresent(reasoningEffort, forKey: .reasoningEffort)
        try container.encode(cwd, forKey: .cwd)
        try container.encode(cliVersion, forKey: .cliVersion)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(preview, forKey: .preview)
        try container.encode(sandboxPolicy, forKey: .sandboxPolicy)
        try container.encode(approvalMode, forKey: .approvalMode)
        try container.encode(tokensUsed, forKey: .tokensUsed)
        try container.encodeIfPresent(firstUserMessage, forKey: .firstUserMessage)
        if let archivedAt {
            try container.encode(stateEncodeRFC3339(archivedAt), forKey: .archivedAt)
        }
        try container.encodeIfPresent(section, forKey: .section)
        try container.encodeIfPresent(sectionPosition, forKey: .sectionPosition)
        if let sectionEnteredAt {
            try container.encode(stateEncodeRFC3339(sectionEnteredAt), forKey: .sectionEnteredAt)
        }
        try container.encodeIfPresent(projectId, forKey: .projectId)
        try container.encodeIfPresent(daybreakEnabled, forKey: .daybreakEnabled)
        try container.encodeIfPresent(gitSha, forKey: .gitSha)
        try container.encodeIfPresent(gitBranch, forKey: .gitBranch)
        try container.encodeIfPresent(gitOriginUrl, forKey: .gitOriginUrl)
    }

    init(row: ThreadRow) throws {
        id = try ThreadId.fromString(row.id)
        originator = row.originator
        creatorUserId = row.creatorUserId
        creatorAccountId = row.creatorAccountId
        rolloutPath = row.rolloutPath
        createdAt = try epochMillisToDatetime(row.createdAt)
        updatedAt = try epochMillisToDatetime(row.updatedAt)
        recencyAt = try epochMillisToDatetime(row.recencyAt)
        source = row.source
        guard let historyMode = ThreadHistoryMode(rawValue: row.historyMode) else {
            throw StateModelError("unknown thread history mode `\(row.historyMode)`")
        }
        self.historyMode = historyMode
        threadSource = row.threadSource.map { ThreadSource($0) }
        agentNickname = row.agentNickname
        agentRole = row.agentRole
        agentPath = row.agentPath
        modelProvider = row.modelProvider
        model = row.model
        reasoningEffort = row.reasoningEffort.flatMap { ReasoningEffort(string: $0) }
        cwd = row.cwd
        cliVersion = row.cliVersion
        title = row.title
        name = row.name
        preview = row.preview.isEmpty ? nil : row.preview
        sandboxPolicy = row.sandboxPolicy
        approvalMode = row.approvalMode
        tokensUsed = row.tokensUsed
        firstUserMessage = row.firstUserMessage.isEmpty ? nil : row.firstUserMessage
        archivedAt = try row.archivedAt.map(epochSecondsToDatetime)
        switch (row.section, row.sectionName) {
        case (let id?, let name?):
            section = try ThreadSection(id: id, name: name, appearanceJSON: row.sectionAppearance)
        case (nil, nil):
            section = nil
        case (let id?, nil):
            throw StateModelError("thread references an unknown section: \(id)")
        case (nil, let name?):
            throw StateModelError("thread has a section name without a section id: \(name)")
        }
        sectionPosition = row.sectionPosition
        sectionEnteredAt = try row.sectionEnteredAtMs.map(epochMillisToDatetime)
        projectId = row.projectId
        daybreakEnabled = row.daybreakEnabled
        gitSha = row.gitSha
        gitBranch = row.gitBranch
        if let origin = row.gitOriginUrl {
            gitOriginUrl = try? SanitizedGitUrl(parsing: origin)
        } else {
            gitOriginUrl = nil
        }
    }

    /// Preserve SQLite-owned Git fields when rollout-derived metadata is reconciled.
    public mutating func preferExistingGitInfo(_ existing: ThreadMetadata) {
        if historyMode == .paginated && existing.historyMode == .paginated {
            gitSha = existing.gitSha
            gitBranch = existing.gitBranch
            gitOriginUrl = existing.gitOriginUrl
            return
        }
        if existing.gitSha != nil {
            gitSha = existing.gitSha
        }
        if existing.gitBranch != nil {
            gitBranch = existing.gitBranch
        }
        if existing.gitOriginUrl != nil {
            gitOriginUrl = existing.gitOriginUrl
        }
    }

    /// Preserve an existing user-facing title when reconciling rollout-derived metadata.
    public mutating func preferExistingExplicitTitle(_ existing: ThreadMetadata) {
        let existingTitle = existing.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if existingTitle.isEmpty
            || existing.firstUserMessage?.trimmingCharacters(in: .whitespacesAndNewlines) == existingTitle
        {
            return
        }

        let title = self.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty
            || firstUserMessage?.trimmingCharacters(in: .whitespacesAndNewlines) == title
            || (title == GUARDIAN_THREAD_TITLE && metadataIsGuardianReview(self))
        {
            self.title = existing.title
        }
    }

    /// Return the list of field names that differ between `self` and `other`.
    public func diffFields(_ other: ThreadMetadata) -> [String] {
        var diffs: [String] = []
        if id != other.id { diffs.append("id") }
        if rolloutPath != other.rolloutPath { diffs.append("rollout_path") }
        if createdAt != other.createdAt { diffs.append("created_at") }
        if updatedAt != other.updatedAt { diffs.append("updated_at") }
        if source != other.source { diffs.append("source") }
        if creatorUserId != other.creatorUserId { diffs.append("creator_user_id") }
        if creatorAccountId != other.creatorAccountId { diffs.append("creator_account_id") }
        if originator != other.originator { diffs.append("originator") }
        if agentNickname != other.agentNickname { diffs.append("agent_nickname") }
        if agentRole != other.agentRole { diffs.append("agent_role") }
        if agentPath != other.agentPath { diffs.append("agent_path") }
        if modelProvider != other.modelProvider { diffs.append("model_provider") }
        if model != other.model { diffs.append("model") }
        if reasoningEffort != other.reasoningEffort { diffs.append("reasoning_effort") }
        if cwd != other.cwd { diffs.append("cwd") }
        if cliVersion != other.cliVersion { diffs.append("cli_version") }
        if title != other.title { diffs.append("title") }
        if name != other.name { diffs.append("name") }
        if preview != other.preview { diffs.append("preview") }
        if sandboxPolicy != other.sandboxPolicy { diffs.append("sandbox_policy") }
        if approvalMode != other.approvalMode { diffs.append("approval_mode") }
        if tokensUsed != other.tokensUsed { diffs.append("tokens_used") }
        if firstUserMessage != other.firstUserMessage { diffs.append("first_user_message") }
        if archivedAt != other.archivedAt { diffs.append("archived_at") }
        if section != other.section { diffs.append("section") }
        if sectionPosition != other.sectionPosition { diffs.append("section_position") }
        if sectionEnteredAt != other.sectionEnteredAt { diffs.append("section_entered_at") }
        if projectId != other.projectId { diffs.append("project_id") }
        if daybreakEnabled != other.daybreakEnabled { diffs.append("daybreak_enabled") }
        if gitSha != other.gitSha { diffs.append("git_sha") }
        if gitBranch != other.gitBranch { diffs.append("git_branch") }
        if gitOriginUrl != other.gitOriginUrl { diffs.append("git_origin_url") }
        return diffs
    }
}

/// Builder data required to construct `ThreadMetadata` without parsing filenames.
public struct ThreadMetadataBuilder: Codable, Equatable, Sendable {
    public var originator: String?
    public var creatorUserId: String?
    public var creatorAccountId: String?
    public var id: ThreadId
    public var rolloutPath: String
    public var createdAt: Date
    public var updatedAt: Date?
    public var recencyAt: Date?
    public var source: SessionSource
    public var historyMode: ThreadHistoryMode
    public var threadSource: ThreadSource?
    public var agentNickname: String?
    public var agentRole: String?
    public var agentPath: String?
    public var modelProvider: String?
    public var cwd: String
    public var cliVersion: String?
    public var sandboxPolicy: SandboxPolicy
    public var approvalMode: AskForApproval
    public var archivedAt: Date?
    public var gitSha: String?
    public var gitBranch: String?
    public var gitOriginUrl: SanitizedGitUrl?

    enum CodingKeys: String, CodingKey {
        case originator
        case creatorUserId = "creator_user_id"
        case creatorAccountId = "creator_account_id"
        case id
        case rolloutPath = "rollout_path"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case recencyAt = "recency_at"
        case source
        case historyMode = "history_mode"
        case threadSource = "thread_source"
        case agentNickname = "agent_nickname"
        case agentRole = "agent_role"
        case agentPath = "agent_path"
        case modelProvider = "model_provider"
        case cwd
        case cliVersion = "cli_version"
        case sandboxPolicy = "sandbox_policy"
        case approvalMode = "approval_mode"
        case archivedAt = "archived_at"
        case gitSha = "git_sha"
        case gitBranch = "git_branch"
        case gitOriginUrl = "git_origin_url"
    }

    /// Create a new builder with required fields and sensible defaults.
    public init(
        id: ThreadId,
        rolloutPath: String,
        createdAt: Date,
        source: SessionSource
    ) {
        self.id = id
        self.rolloutPath = rolloutPath
        self.createdAt = createdAt
        self.updatedAt = nil
        self.recencyAt = nil
        self.originator = nil
        self.creatorUserId = nil
        self.creatorAccountId = nil
        self.source = source
        self.historyMode = .legacy
        self.threadSource = nil
        self.agentNickname = nil
        self.agentRole = nil
        self.agentPath = nil
        self.modelProvider = nil
        self.cwd = ""
        self.cliVersion = nil
        self.sandboxPolicy = .newReadOnlyPolicy()
        self.approvalMode = .onRequest
        self.archivedAt = nil
        self.gitSha = nil
        self.gitBranch = nil
        self.gitOriginUrl = nil
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        originator = try container.decodeIfPresent(String.self, forKey: .originator)
        creatorUserId = try container.decodeIfPresent(String.self, forKey: .creatorUserId)
        creatorAccountId = try container.decodeIfPresent(String.self, forKey: .creatorAccountId)
        id = try container.decode(ThreadId.self, forKey: .id)
        rolloutPath = try container.decode(String.self, forKey: .rolloutPath)
        createdAt = try stateDecodeRFC3339(try container.decode(String.self, forKey: .createdAt))
        if let raw = try container.decodeIfPresent(String.self, forKey: .updatedAt) {
            updatedAt = try stateDecodeRFC3339(raw)
        } else {
            updatedAt = nil
        }
        if let raw = try container.decodeIfPresent(String.self, forKey: .recencyAt) {
            recencyAt = try stateDecodeRFC3339(raw)
        } else {
            recencyAt = nil
        }
        source = try container.decode(SessionSource.self, forKey: .source)
        historyMode = try container.decode(ThreadHistoryMode.self, forKey: .historyMode)
        threadSource = try container.decodeIfPresent(ThreadSource.self, forKey: .threadSource)
        agentNickname = try container.decodeIfPresent(String.self, forKey: .agentNickname)
        agentRole = try container.decodeIfPresent(String.self, forKey: .agentRole)
        agentPath = try container.decodeIfPresent(String.self, forKey: .agentPath)
        modelProvider = try container.decodeIfPresent(String.self, forKey: .modelProvider)
        cwd = try container.decode(String.self, forKey: .cwd)
        cliVersion = try container.decodeIfPresent(String.self, forKey: .cliVersion)
        sandboxPolicy = try container.decode(SandboxPolicy.self, forKey: .sandboxPolicy)
        approvalMode = try container.decode(AskForApproval.self, forKey: .approvalMode)
        if let raw = try container.decodeIfPresent(String.self, forKey: .archivedAt) {
            archivedAt = try stateDecodeRFC3339(raw)
        } else {
            archivedAt = nil
        }
        gitSha = try container.decodeIfPresent(String.self, forKey: .gitSha)
        gitBranch = try container.decodeIfPresent(String.self, forKey: .gitBranch)
        gitOriginUrl = try container.decodeIfPresent(SanitizedGitUrl.self, forKey: .gitOriginUrl)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(originator, forKey: .originator)
        try container.encodeIfPresent(creatorUserId, forKey: .creatorUserId)
        try container.encodeIfPresent(creatorAccountId, forKey: .creatorAccountId)
        try container.encode(id, forKey: .id)
        try container.encode(rolloutPath, forKey: .rolloutPath)
        try container.encode(stateEncodeRFC3339(createdAt), forKey: .createdAt)
        if let updatedAt {
            try container.encode(stateEncodeRFC3339(updatedAt), forKey: .updatedAt)
        }
        if let recencyAt {
            try container.encode(stateEncodeRFC3339(recencyAt), forKey: .recencyAt)
        }
        try container.encode(source, forKey: .source)
        try container.encode(historyMode, forKey: .historyMode)
        try container.encodeIfPresent(threadSource, forKey: .threadSource)
        try container.encodeIfPresent(agentNickname, forKey: .agentNickname)
        try container.encodeIfPresent(agentRole, forKey: .agentRole)
        try container.encodeIfPresent(agentPath, forKey: .agentPath)
        try container.encodeIfPresent(modelProvider, forKey: .modelProvider)
        try container.encode(cwd, forKey: .cwd)
        try container.encodeIfPresent(cliVersion, forKey: .cliVersion)
        try container.encode(sandboxPolicy, forKey: .sandboxPolicy)
        try container.encode(approvalMode, forKey: .approvalMode)
        if let archivedAt {
            try container.encode(stateEncodeRFC3339(archivedAt), forKey: .archivedAt)
        }
        try container.encodeIfPresent(gitSha, forKey: .gitSha)
        try container.encodeIfPresent(gitBranch, forKey: .gitBranch)
        try container.encodeIfPresent(gitOriginUrl, forKey: .gitOriginUrl)
    }

    /// Build canonical thread metadata, filling missing values from defaults.
    public func build(defaultProvider: String) -> ThreadMetadata {
        let source = enumToString(self.source)
        let sandboxPolicy = enumToString(self.sandboxPolicy)
        let approvalMode = enumToString(self.approvalMode)
        let createdAt = canonicalizeDatetime(self.createdAt)
        let updatedAt = self.updatedAt.map(canonicalizeDatetime) ?? createdAt
        let recencyAt = self.recencyAt.map(canonicalizeDatetime) ?? updatedAt
        let guardianReview = isGuardianReviewSource(self.source)
        return ThreadMetadata(
            originator: originator,
            creatorUserId: creatorUserId,
            creatorAccountId: creatorAccountId,
            id: id,
            rolloutPath: rolloutPath,
            createdAt: createdAt,
            updatedAt: updatedAt,
            recencyAt: recencyAt,
            source: source,
            historyMode: historyMode,
            threadSource: threadSource,
            agentNickname: agentNickname,
            agentRole: agentRole,
            agentPath: agentPath ?? sessionSourceAgentPath(self.source),
            modelProvider: modelProvider ?? defaultProvider,
            model: nil,
            reasoningEffort: nil,
            cwd: cwd,
            cliVersion: cliVersion ?? "",
            title: guardianReview ? GUARDIAN_THREAD_TITLE : "",
            name: (guardianReview && historyMode == .paginated) ? GUARDIAN_THREAD_TITLE : nil,
            preview: guardianReview ? GUARDIAN_THREAD_PREVIEW : nil,
            sandboxPolicy: sandboxPolicy,
            approvalMode: approvalMode,
            tokensUsed: 0,
            firstUserMessage: nil,
            archivedAt: self.archivedAt.map(canonicalizeDatetime),
            section: nil,
            sectionPosition: nil,
            sectionEnteredAt: nil,
            projectId: nil,
            daybreakEnabled: nil,
            gitSha: gitSha,
            gitBranch: gitBranch,
            gitOriginUrl: gitOriginUrl
        )
    }
}

struct ThreadRow: Equatable, Sendable {
    var originator: String?
    var creatorUserId: String?
    var creatorAccountId: String?
    var id: String
    var rolloutPath: String
    var createdAt: Int64
    var updatedAt: Int64
    var recencyAt: Int64
    var source: String
    var historyMode: String
    var threadSource: String?
    var agentNickname: String?
    var agentRole: String?
    var agentPath: String?
    var modelProvider: String
    var model: String?
    var reasoningEffort: String?
    var cwd: String
    var cliVersion: String
    var title: String
    var name: String?
    var preview: String
    var sandboxPolicy: String
    var approvalMode: String
    var tokensUsed: Int64
    var firstUserMessage: String
    var archivedAt: Int64?
    var section: String?
    var sectionName: String?
    var sectionAppearance: String?
    var sectionPosition: Int64?
    var sectionEnteredAtMs: Int64?
    var projectId: String?
    var daybreakEnabled: Bool?
    var gitSha: String?
    var gitBranch: String?
    var gitOriginUrl: String?
}

func anchorFromItem(
    _ item: ThreadMetadata,
    sortKey: SortKey,
    includeThreadIdTiebreaker: Bool
) -> Anchor? {
    let ts: Date
    switch sortKey {
    case .createdAt:
        ts = item.createdAt
    case .updatedAt:
        ts = item.updatedAt
    case .recencyAt:
        ts = item.recencyAt
    case .sectionPosition:
        guard let position = item.sectionPosition else { return nil }
        ts = Date(timeIntervalSince1970: TimeInterval(position) / 1000.0)
    }
    let includeId = includeThreadIdTiebreaker
        || sortKey == .recencyAt
        || sortKey == .sectionPosition
    return Anchor(ts: ts, id: includeId ? item.id : nil)
}

func datetimeToEpochMillis(_ date: Date) -> Int64 {
    Int64((date.timeIntervalSince1970 * 1000.0).rounded(.towardZero))
}

func datetimeToEpochSeconds(_ date: Date) -> Int64 {
    Int64(date.timeIntervalSince1970.rounded(.towardZero))
}

func epochMillisToDatetime(_ value: Int64) throws -> Date {
    // Values older than 2020 if interpreted as milliseconds are legacy second-precision rows.
    let minEpochMillis: Int64 = 1_577_836_800_000
    let millis: Int64
    if value < minEpochMillis {
        let (product, overflow) = value.multipliedReportingOverflow(by: 1000)
        millis = overflow ? (value > 0 ? Int64.max : Int64.min) : product
    } else {
        millis = value
    }
    return Date(timeIntervalSince1970: TimeInterval(millis) / 1000.0)
}

func epochSecondsToDatetime(_ value: Int64) throws -> Date {
    Date(timeIntervalSince1970: TimeInterval(value))
}

/// Statistics about a backfill operation.
public struct BackfillStats: Codable, Equatable, Sendable {
    /// The number of rollout files scanned.
    public var scanned: Int
    /// The number of rows upserted successfully.
    public var upserted: Int
    /// The number of rows that failed to upsert.
    public var failed: Int

    public init(scanned: Int, upserted: Int, failed: Int) {
        self.scanned = scanned
        self.upserted = upserted
        self.failed = failed
    }
}

func canonicalizeDatetime(_ date: Date) -> Date {
    (try? epochMillisToDatetime(datetimeToEpochMillis(date))) ?? date
}

func enumToString<T: Encodable>(_ value: T) -> String {
    let encoder = JSONEncoder()
    guard let data = try? encoder.encode(value) else { return "" }
    if let string = try? JSONDecoder().decode(String.self, from: data) {
        return string
    }
    return String(data: data, encoding: .utf8) ?? ""
}

func metadataIsGuardianReview(_ metadata: ThreadMetadata) -> Bool {
    guard let data = metadata.source.data(using: .utf8),
          let source = try? JSONDecoder().decode(SessionSource.self, from: data)
    else {
        return false
    }
    return isGuardianReviewSource(source)
}

func sessionSourceAgentPath(_ source: SessionSource) -> String? {
    if case .subAgent(.threadSpawn(_, _, let path, _, _)) = source {
        return path?.asStr
    }
    return nil
}
