//
//  types.swift
//  CodexThreadStore
//
//  Port of codex-rs/thread-store/src/types.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Adaptations:
//  - `PathBuf` / `AbsolutePathBuf` → `String` (CodexUtils is not a
//    CodexThreadStore dependency).
//  - `DateTime<Utc>` → `Date` encoded as RFC 3339.
//  - `ThreadMemoryMode` lives here until protocol.swift ports it.
//  - `ThreadSection` is defined in thread_sections.swift (CodexState model
//    unported).
//  - `ThreadTimelineEntry` (app-server crate) is a JSON stub.
//  - `PreparedFork` drops the backend-owned source reservation.
//  - `ClearableField<T>` is `T??` with optional_option wire semantics.
//

import CodexHistory
import CodexProtocol
import Foundation

/// Optional field patch where omission leaves a value unchanged and `.some(nil)` clears it.
public typealias ClearableField<T> = T??

/// Memory mode associated with a live thread.
///
/// Port of `codex_protocol::protocol::ThreadMemoryMode` (`rename_all = "lowercase"`).
public enum ThreadMemoryMode: String, Codable, Equatable, Sendable {
    case enabled
    case disabled
}

/// Thread-scoped metadata used when opening live persistence.
public struct ThreadPersistenceMetadata: Codable, Equatable, Sendable {
    public var cwd: String?
    public var modelProvider: String
    public var memoryMode: ThreadMemoryMode

    enum CodingKeys: String, CodingKey {
        case cwd
        case modelProvider = "model_provider"
        case memoryMode = "memory_mode"
    }

    public init(
        cwd: String? = nil,
        modelProvider: String,
        memoryMode: ThreadMemoryMode
    ) {
        self.cwd = cwd
        self.modelProvider = modelProvider
        self.memoryMode = memoryMode
    }
}

/// Extra configuration fields for a thread.
public struct ExtraConfig: Codable, Equatable, Sendable {
    public init() {}
}

/// Parameters required to create a persisted thread.
public struct CreateThreadParams: Codable, Sendable {
    public var creatorUserId: String?
    public var creatorAccountId: String?
    public var sessionId: SessionId
    public var threadId: ThreadId
    public var extraConfig: ExtraConfig?
    public var forkedFromId: ThreadId?
    public var parentThreadId: ThreadId?
    public var source: SessionSource
    public var threadSource: ThreadSource?
    public var originator: String
    public var baseInstructions: BaseInstructions
    public var dynamicTools: [DynamicToolSpec]
    public var selectedCapabilityRoots: [SelectedCapabilityRoot]
    public var multiAgentVersion: MultiAgentVersion?
    public var historyMode: ThreadHistoryMode
    public var historyBase: HistoryPosition?
    public var subagentHistoryStartOrdinal: UInt64?
    public var initialWindowId: String
    public var runtimeWorkspaceRoots: [String]?
    public var metadata: ThreadPersistenceMetadata

    enum CodingKeys: String, CodingKey {
        case originator, source, metadata
        case creatorUserId = "creator_user_id"
        case creatorAccountId = "creator_account_id"
        case sessionId = "session_id"
        case threadId = "thread_id"
        case extraConfig = "extra_config"
        case forkedFromId = "forked_from_id"
        case parentThreadId = "parent_thread_id"
        case threadSource = "thread_source"
        case baseInstructions = "base_instructions"
        case dynamicTools = "dynamic_tools"
        case selectedCapabilityRoots = "selected_capability_roots"
        case multiAgentVersion = "multi_agent_version"
        case historyMode = "history_mode"
        case historyBase = "history_base"
        case subagentHistoryStartOrdinal = "subagent_history_start_ordinal"
        case initialWindowId = "initial_window_id"
        case runtimeWorkspaceRoots = "runtime_workspace_roots"
    }

    public init(
        creatorUserId: String? = nil,
        creatorAccountId: String? = nil,
        sessionId: SessionId,
        threadId: ThreadId,
        extraConfig: ExtraConfig? = nil,
        forkedFromId: ThreadId? = nil,
        parentThreadId: ThreadId? = nil,
        source: SessionSource,
        threadSource: ThreadSource? = nil,
        originator: String,
        baseInstructions: BaseInstructions = BaseInstructions(),
        dynamicTools: [DynamicToolSpec] = [],
        selectedCapabilityRoots: [SelectedCapabilityRoot] = [],
        multiAgentVersion: MultiAgentVersion? = nil,
        historyMode: ThreadHistoryMode = .legacy,
        historyBase: HistoryPosition? = nil,
        subagentHistoryStartOrdinal: UInt64? = nil,
        initialWindowId: String,
        runtimeWorkspaceRoots: [String]? = nil,
        metadata: ThreadPersistenceMetadata
    ) {
        self.creatorUserId = creatorUserId
        self.creatorAccountId = creatorAccountId
        self.sessionId = sessionId
        self.threadId = threadId
        self.extraConfig = extraConfig
        self.forkedFromId = forkedFromId
        self.parentThreadId = parentThreadId
        self.source = source
        self.threadSource = threadSource
        self.originator = originator
        self.baseInstructions = baseInstructions
        self.dynamicTools = dynamicTools
        self.selectedCapabilityRoots = selectedCapabilityRoots
        self.multiAgentVersion = multiAgentVersion
        self.historyMode = historyMode
        self.historyBase = historyBase
        self.subagentHistoryStartOrdinal = subagentHistoryStartOrdinal
        self.initialWindowId = initialWindowId
        self.runtimeWorkspaceRoots = runtimeWorkspaceRoots
        self.metadata = metadata
    }
}

/// Parameters required to reopen persistence for an existing thread.
public struct ResumeThreadParams: Codable, Sendable {
    public var threadId: ThreadId
    public var rolloutPath: String?
    public var history: [RolloutItem]?
    public var includeArchived: Bool
    public var metadata: ThreadPersistenceMetadata

    enum CodingKeys: String, CodingKey {
        case history, metadata
        case threadId = "thread_id"
        case rolloutPath = "rollout_path"
        case includeArchived = "include_archived"
    }

    public init(
        threadId: ThreadId,
        rolloutPath: String? = nil,
        history: [RolloutItem]? = nil,
        includeArchived: Bool,
        metadata: ThreadPersistenceMetadata
    ) {
        self.threadId = threadId
        self.rolloutPath = rolloutPath
        self.history = history
        self.includeArchived = includeArchived
        self.metadata = metadata
    }
}

func canonicalHistoryModeFromRolloutItems(_ items: [RolloutItem]) -> ThreadHistoryMode {
    for item in items {
        if case .sessionMeta(let metaLine) = item {
            return metaLine.meta.historyMode
        }
    }
    return .legacy
}

/// Parameters for appending rollout items to a live thread.
public struct AppendThreadItemsParams: Sendable {
    public var threadId: ThreadId
    public var items: [RolloutItem]

    public init(threadId: ThreadId, items: [RolloutItem]) {
        self.threadId = threadId
        self.items = items
    }
}

/// Parameters for loading persisted history for resume, fork, and memory jobs.
public struct LoadThreadHistoryParams: Codable, Equatable, Sendable {
    public var threadId: ThreadId
    public var includeArchived: Bool

    enum CodingKeys: String, CodingKey {
        case threadId = "thread_id"
        case includeArchived = "include_archived"
    }

    public init(threadId: ThreadId, includeArchived: Bool) {
        self.threadId = threadId
        self.includeArchived = includeArchived
    }
}

/// Persisted rollout history for a thread, without any filesystem path requirement.
public struct StoredThreadHistory: Codable, Sendable {
    public var threadId: ThreadId
    public var items: [RolloutItem]

    enum CodingKeys: String, CodingKey {
        case items
        case threadId = "thread_id"
    }

    public init(threadId: ThreadId, items: [RolloutItem]) {
        self.threadId = threadId
        self.items = items
    }
}

/// Persisted rollout items needed to reconstruct the latest model-visible context.
public struct StoredModelContext: Codable, Sendable {
    public var threadId: ThreadId
    public var items: [RolloutItem]

    enum CodingKeys: String, CodingKey {
        case items
        case threadId = "thread_id"
    }

    public init(threadId: ThreadId, items: [RolloutItem]) {
        self.threadId = threadId
        self.items = items
    }
}

/// Requested boundary for inheriting a paginated thread's history.
public enum ForkBoundary: Codable, Equatable, Sendable {
    case latest
    case throughTurn(String)
    case beforeTurn(String)

    public init(from decoder: any Decoder) throws {
        if let raw = try? decoder.singleValueContainer().decode(String.self), raw == "Latest" {
            self = .latest
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let turn = try container.decodeIfPresent(String.self, forKey: .throughTurn) {
            self = .throughTurn(turn)
        } else if let turn = try container.decodeIfPresent(String.self, forKey: .beforeTurn) {
            self = .beforeTurn(turn)
        } else if container.contains(.latest) {
            self = .latest
        } else {
            throw DecodingError.dataCorruptedError(
                forKey: .latest, in: container, debugDescription: "Unknown ForkBoundary")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .latest:
            var container = encoder.singleValueContainer()
            try container.encode("Latest")
        case .throughTurn(let turn):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(turn, forKey: .throughTurn)
        case .beforeTurn(let turn):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(turn, forKey: .beforeTurn)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case latest = "Latest"
        case throughTurn = "ThroughTurn"
        case beforeTurn = "BeforeTurn"
    }
}

/// Parameters for freezing the source history used to initialize a fork.
public struct PrepareForkParams: Codable, Equatable, Sendable {
    public var threadId: ThreadId
    public var boundary: ForkBoundary

    enum CodingKeys: String, CodingKey {
        case threadId = "thread_id"
        case boundary
    }

    public init(threadId: ThreadId, boundary: ForkBoundary) {
        self.threadId = threadId
        self.boundary = boundary
    }
}

/// Parameters for reverting a paginated thread's durable history.
public struct RevertThreadParams: Codable, Equatable, Sendable {
    public var threadId: ThreadId
    public var beforeTurnId: String
    public var multiAgentVersion: MultiAgentVersion?

    enum CodingKeys: String, CodingKey {
        case threadId = "thread_id"
        case beforeTurnId = "before_turn_id"
        case multiAgentVersion = "multi_agent_version"
    }

    public init(
        threadId: ThreadId,
        beforeTurnId: String,
        multiAgentVersion: MultiAgentVersion? = nil
    ) {
        self.threadId = threadId
        self.beforeTurnId = beforeTurnId
        self.multiAgentVersion = multiAgentVersion
    }
}

/// Frozen source history and model context for a reference-backed fork.
public struct PreparedFork: Sendable {
    public var sourceThreadId: ThreadId
    public var historyBase: HistoryPosition?
    public var modelContext: [RolloutItem]

    public init(
        sourceThreadId: ThreadId,
        historyBase: HistoryPosition?,
        modelContext: [RolloutItem]
    ) {
        self.sourceThreadId = sourceThreadId
        self.historyBase = historyBase
        self.modelContext = modelContext
    }
}

/// Parameters for reading a thread summary and optionally its replay history.
public struct ReadThreadParams: Codable, Equatable, Sendable {
    public var threadId: ThreadId
    public var includeArchived: Bool
    public var includeHistory: Bool

    enum CodingKeys: String, CodingKey {
        case threadId = "thread_id"
        case includeArchived = "include_archived"
        case includeHistory = "include_history"
    }

    public init(threadId: ThreadId, includeArchived: Bool, includeHistory: Bool) {
        self.threadId = threadId
        self.includeArchived = includeArchived
        self.includeHistory = includeHistory
    }
}

/// Parameters for reading a local rollout-backed thread by path.
public struct ReadThreadByRolloutPathParams: Codable, Equatable, Sendable {
    public var rolloutPath: String
    public var includeArchived: Bool
    public var includeHistory: Bool

    enum CodingKeys: String, CodingKey {
        case rolloutPath = "rollout_path"
        case includeArchived = "include_archived"
        case includeHistory = "include_history"
    }

    public init(rolloutPath: String, includeArchived: Bool, includeHistory: Bool) {
        self.rolloutPath = rolloutPath
        self.includeArchived = includeArchived
        self.includeHistory = includeHistory
    }
}

/// The sort key to use when listing stored threads.
public enum ThreadSortKey: String, Codable, Equatable, Sendable {
    case createdAt = "CreatedAt"
    case updatedAt = "UpdatedAt"
    case recencyAt = "RecencyAt"
    case sectionPosition = "SectionPosition"

    public static let `default`: ThreadSortKey = .createdAt
}

/// The direction to use when listing stored threads.
public enum SortDirection: String, Codable, Equatable, Sendable {
    case asc = "Asc"
    case desc = "Desc"

    public static let `default`: SortDirection = .desc
}

/// Spawn-graph relationship used to filter thread listings.
public enum ThreadRelationFilter: Codable, Equatable, Sendable {
    case directChildrenOf(ThreadId)
    case descendantsOf(ThreadId)

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let id = try container.decodeIfPresent(ThreadId.self, forKey: .directChildrenOf) {
            self = .directChildrenOf(id)
        } else if let id = try container.decodeIfPresent(ThreadId.self, forKey: .descendantsOf) {
            self = .descendantsOf(id)
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unknown ThreadRelationFilter"))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .directChildrenOf(let id):
            try container.encode(id, forKey: .directChildrenOf)
        case .descendantsOf(let id):
            try container.encode(id, forKey: .descendantsOf)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case directChildrenOf = "DirectChildrenOf"
        case descendantsOf = "DescendantsOf"
    }
}

/// Parameters for listing threads.
public struct ListThreadsParams: Codable, Equatable, Sendable {
    public var pageSize: Int
    public var cursor: String?
    public var sortKey: ThreadSortKey
    public var sortDirection: SortDirection
    public var allowedSources: [SessionSource]
    public var modelProviders: [String]?
    public var cwdFilters: [String]?
    public var section: ClearableField<String>
    public var projectId: ClearableField<String>
    public var archived: Bool
    public var searchTerm: String?
    public var relationFilter: ThreadRelationFilter?
    public var useStateDbOnly: Bool

    enum CodingKeys: String, CodingKey {
        case cursor, archived, section
        case pageSize = "page_size"
        case sortKey = "sort_key"
        case sortDirection = "sort_direction"
        case allowedSources = "allowed_sources"
        case modelProviders = "model_providers"
        case cwdFilters = "cwd_filters"
        case projectId = "project_id"
        case searchTerm = "search_term"
        case relationFilter = "relation_filter"
        case useStateDbOnly = "use_state_db_only"
    }

    public init(
        pageSize: Int,
        cursor: String? = nil,
        sortKey: ThreadSortKey = .default,
        sortDirection: SortDirection = .default,
        allowedSources: [SessionSource] = [],
        modelProviders: [String]? = nil,
        cwdFilters: [String]? = nil,
        section: ClearableField<String> = nil,
        projectId: ClearableField<String> = nil,
        archived: Bool,
        searchTerm: String? = nil,
        relationFilter: ThreadRelationFilter? = nil,
        useStateDbOnly: Bool = false
    ) {
        self.pageSize = pageSize
        self.cursor = cursor
        self.sortKey = sortKey
        self.sortDirection = sortDirection
        self.allowedSources = allowedSources
        self.modelProviders = modelProviders
        self.cwdFilters = cwdFilters
        self.section = section
        self.projectId = projectId
        self.archived = archived
        self.searchTerm = searchTerm
        self.relationFilter = relationFilter
        self.useStateDbOnly = useStateDbOnly
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pageSize = try container.decode(Int.self, forKey: .pageSize)
        cursor = try container.decodeIfPresent(String.self, forKey: .cursor)
        sortKey = try container.decode(ThreadSortKey.self, forKey: .sortKey)
        sortDirection = try container.decode(SortDirection.self, forKey: .sortDirection)
        allowedSources = try container.decode([SessionSource].self, forKey: .allowedSources)
        modelProviders = try container.decodeIfPresent([String].self, forKey: .modelProviders)
        cwdFilters = try container.decodeIfPresent([String].self, forKey: .cwdFilters)
        section = try decodeClearable(container, forKey: .section)
        projectId = try decodeClearable(container, forKey: .projectId)
        archived = try container.decode(Bool.self, forKey: .archived)
        searchTerm = try container.decodeIfPresent(String.self, forKey: .searchTerm)
        relationFilter = try container.decodeIfPresent(ThreadRelationFilter.self, forKey: .relationFilter)
        useStateDbOnly = try container.decode(Bool.self, forKey: .useStateDbOnly)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pageSize, forKey: .pageSize)
        try container.encodeIfPresent(cursor, forKey: .cursor)
        try container.encode(sortKey, forKey: .sortKey)
        try container.encode(sortDirection, forKey: .sortDirection)
        try container.encode(allowedSources, forKey: .allowedSources)
        try container.encodeIfPresent(modelProviders, forKey: .modelProviders)
        try container.encodeIfPresent(cwdFilters, forKey: .cwdFilters)
        try encodeClearable(section, forKey: .section, into: &container)
        try encodeClearable(projectId, forKey: .projectId, into: &container)
        try container.encode(archived, forKey: .archived)
        try container.encodeIfPresent(searchTerm, forKey: .searchTerm)
        try container.encodeIfPresent(relationFilter, forKey: .relationFilter)
        try container.encode(useStateDbOnly, forKey: .useStateDbOnly)
    }
}

/// Parameters for searching thread content.
public struct SearchThreadsParams: Codable, Equatable, Sendable {
    public var pageSize: Int
    public var cursor: String?
    public var sortKey: ThreadSortKey
    public var sortDirection: SortDirection
    public var allowedSources: [SessionSource]
    public var archived: Bool
    public var searchTerm: String

    enum CodingKeys: String, CodingKey {
        case cursor, archived
        case pageSize = "page_size"
        case sortKey = "sort_key"
        case sortDirection = "sort_direction"
        case allowedSources = "allowed_sources"
        case searchTerm = "search_term"
    }

    public init(
        pageSize: Int,
        cursor: String? = nil,
        sortKey: ThreadSortKey = .default,
        sortDirection: SortDirection = .default,
        allowedSources: [SessionSource] = [],
        archived: Bool,
        searchTerm: String
    ) {
        self.pageSize = pageSize
        self.cursor = cursor
        self.sortKey = sortKey
        self.sortDirection = sortDirection
        self.allowedSources = allowedSources
        self.archived = archived
        self.searchTerm = searchTerm
    }
}

/// A page of stored thread records.
public struct ThreadPage: Codable, Sendable {
    public var items: [StoredThread]
    public var nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case items
        case nextCursor = "next_cursor"
    }

    public init(items: [StoredThread], nextCursor: String? = nil) {
        self.items = items
        self.nextCursor = nextCursor
    }
}

public struct StoredThreadSearchResult: Codable, Sendable {
    public var thread: StoredThread
    public var snippet: String

    public init(thread: StoredThread, snippet: String) {
        self.thread = thread
        self.snippet = snippet
    }
}

/// A page of thread-search results.
public struct ThreadSearchPage: Codable, Sendable {
    public var items: [StoredThreadSearchResult]
    public var nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case items
        case nextCursor = "next_cursor"
    }

    public init(items: [StoredThreadSearchResult], nextCursor: String? = nil) {
        self.items = items
        self.nextCursor = nextCursor
    }
}

/// Requested amount of item detail for stored turns.
public enum StoredTurnItemsView: String, Codable, Equatable, Sendable {
    case notLoaded = "NotLoaded"
    case summary = "Summary"

    public static let `default`: StoredTurnItemsView = .summary
}

/// Store-owned status for a persisted turn.
public enum StoredTurnStatus: String, Codable, Equatable, Sendable {
    case completed = "Completed"
    case interrupted = "Interrupted"
    case failed = "Failed"
    case inProgress = "InProgress"
}

/// Store-owned error details for a failed persisted turn.
public struct StoredTurnError: Codable, Equatable, Sendable {
    public var message: String
    public var codexErrorInfo: CodexErrorInfo?
    public var additionalDetails: String?

    enum CodingKeys: String, CodingKey {
        case message
        case codexErrorInfo
        case additionalDetails
    }

    public init(
        message: String,
        codexErrorInfo: CodexErrorInfo? = nil,
        additionalDetails: String? = nil
    ) {
        self.message = message
        self.codexErrorInfo = codexErrorInfo
        self.additionalDetails = additionalDetails
    }
}

/// Parameters for listing turns within a stored thread.
public struct ListTurnsParams: Codable, Equatable, Sendable {
    public var threadId: ThreadId
    public var includeArchived: Bool
    public var cursor: String?
    public var pageSize: Int
    public var sortDirection: SortDirection
    public var itemsView: StoredTurnItemsView

    enum CodingKeys: String, CodingKey {
        case cursor
        case threadId = "thread_id"
        case includeArchived = "include_archived"
        case pageSize = "page_size"
        case sortDirection = "sort_direction"
        case itemsView = "items_view"
    }

    public init(
        threadId: ThreadId,
        includeArchived: Bool,
        cursor: String? = nil,
        pageSize: Int,
        sortDirection: SortDirection,
        itemsView: StoredTurnItemsView = .default
    ) {
        self.threadId = threadId
        self.includeArchived = includeArchived
        self.cursor = cursor
        self.pageSize = pageSize
        self.sortDirection = sortDirection
        self.itemsView = itemsView
    }
}

/// Store-owned turn representation used by turn pagination APIs.
public struct StoredTurn: Codable, Sendable {
    public var turnId: String
    public var items: [StoredThreadItem]
    public var itemsView: StoredTurnItemsView
    public var status: StoredTurnStatus
    public var error: StoredTurnError?
    public var startedAt: Int64?
    public var completedAt: Int64?
    public var durationMs: Int64?

    enum CodingKeys: String, CodingKey {
        case items, status, error
        case turnId = "turn_id"
        case itemsView = "items_view"
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case durationMs = "duration_ms"
    }

    public init(
        turnId: String,
        items: [StoredThreadItem],
        itemsView: StoredTurnItemsView,
        status: StoredTurnStatus,
        error: StoredTurnError? = nil,
        startedAt: Int64? = nil,
        completedAt: Int64? = nil,
        durationMs: Int64? = nil
    ) {
        self.turnId = turnId
        self.items = items
        self.itemsView = itemsView
        self.status = status
        self.error = error
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.durationMs = durationMs
    }
}

/// A page of stored turns.
public struct TurnPage: Codable, Sendable {
    public var turns: [StoredTurn]
    public var nextCursor: String?
    public var backwardsCursor: String?

    enum CodingKeys: String, CodingKey {
        case turns
        case nextCursor = "next_cursor"
        case backwardsCursor = "backwards_cursor"
    }

    public init(turns: [StoredTurn], nextCursor: String? = nil, backwardsCursor: String? = nil) {
        self.turns = turns
        self.nextCursor = nextCursor
        self.backwardsCursor = backwardsCursor
    }
}

/// Parameters for listing persisted items within a thread.
public struct ListItemsParams: Codable, Equatable, Sendable {
    public var threadId: ThreadId
    public var turnId: String?
    public var includeArchived: Bool
    public var cursor: String?
    public var pageSize: Int
    public var sortDirection: SortDirection
    public var sortKey: ItemSortKey
    public var afterUpdatedAtOrdinal: UInt64?

    enum CodingKeys: String, CodingKey {
        case cursor
        case threadId = "thread_id"
        case turnId = "turn_id"
        case includeArchived = "include_archived"
        case pageSize = "page_size"
        case sortDirection = "sort_direction"
        case sortKey = "sort_key"
        case afterUpdatedAtOrdinal = "after_updated_at_ordinal"
    }

    public init(
        threadId: ThreadId,
        turnId: String? = nil,
        includeArchived: Bool,
        cursor: String? = nil,
        pageSize: Int,
        sortDirection: SortDirection,
        sortKey: ItemSortKey,
        afterUpdatedAtOrdinal: UInt64? = nil
    ) {
        self.threadId = threadId
        self.turnId = turnId
        self.includeArchived = includeArchived
        self.cursor = cursor
        self.pageSize = pageSize
        self.sortDirection = sortDirection
        self.sortKey = sortKey
        self.afterUpdatedAtOrdinal = afterUpdatedAtOrdinal
    }
}

/// The ordinal to use when listing persisted items.
public enum ItemSortKey: String, Codable, Equatable, Sendable {
    case createdAtOrdinal = "CreatedAtOrdinal"
    case updatedAtOrdinal = "UpdatedAtOrdinal"
}

/// A projected app-server `ThreadItem` snapshot within a turn.
public struct StoredThreadItem: Codable, Equatable, Sendable {
    public var turnId: String
    public var itemId: String
    public var updatedAtOrdinal: UInt64
    public var createdAtMs: Int64
    public var startedAtMs: Int64?
    public var completedAtMs: Int64?
    public var itemJson: [UInt8]

    enum CodingKeys: String, CodingKey {
        case turnId = "turn_id"
        case itemId = "item_id"
        case updatedAtOrdinal = "updated_at_ordinal"
        case createdAtMs = "created_at_ms"
        case startedAtMs = "started_at_ms"
        case completedAtMs = "completed_at_ms"
        case itemJson = "item_json"
    }

    public init(
        turnId: String,
        itemId: String,
        updatedAtOrdinal: UInt64,
        createdAtMs: Int64,
        startedAtMs: Int64? = nil,
        completedAtMs: Int64? = nil,
        itemJson: [UInt8]
    ) {
        self.turnId = turnId
        self.itemId = itemId
        self.updatedAtOrdinal = updatedAtOrdinal
        self.createdAtMs = createdAtMs
        self.startedAtMs = startedAtMs
        self.completedAtMs = completedAtMs
        self.itemJson = itemJson
    }
}

/// A page of persisted items within a thread, optionally filtered to a turn.
public struct ItemPage: Codable, Sendable {
    public var items: [StoredThreadItem]
    public var nextCursor: String?
    public var backwardsCursor: String?

    enum CodingKeys: String, CodingKey {
        case items
        case nextCursor = "next_cursor"
        case backwardsCursor = "backwards_cursor"
    }

    public init(items: [StoredThreadItem], nextCursor: String? = nil, backwardsCursor: String? = nil) {
        self.items = items
        self.nextCursor = nextCursor
        self.backwardsCursor = backwardsCursor
    }
}

/// Parameters for reading a bounded mixed thread timeline.
public struct ListTimelineParams: Codable, Equatable, Sendable {
    public var threadId: ThreadId
    public var cursor: String?
    public var pageSize: Int

    enum CodingKeys: String, CodingKey {
        case cursor
        case threadId = "thread_id"
        case pageSize = "page_size"
    }

    public init(threadId: ThreadId, cursor: String? = nil, pageSize: Int) {
        self.threadId = threadId
        self.cursor = cursor
        self.pageSize = pageSize
    }
}

/// Stands in for `codex_app_server_protocol::ThreadTimelineEntry`.
public struct ThreadTimelineEntry: Codable, Equatable, Sendable {
    public var payload: JSONValue

    public init(payload: JSONValue = .null) {
        self.payload = payload
    }
}

/// Ordinary items, realtime facts, and the session state preceding their page.
public struct TimelinePage: Codable, Equatable, Sendable {
    public var items: [ThreadTimelineEntry]
    public var nextCursor: String?
    public var activeRealtimeSessionAtPageStart: String?

    enum CodingKeys: String, CodingKey {
        case items
        case nextCursor = "next_cursor"
        case activeRealtimeSessionAtPageStart = "active_realtime_session_at_page_start"
    }

    public init(
        items: [ThreadTimelineEntry],
        nextCursor: String? = nil,
        activeRealtimeSessionAtPageStart: String? = nil
    ) {
        self.items = items
        self.nextCursor = nextCursor
        self.activeRealtimeSessionAtPageStart = activeRealtimeSessionAtPageStart
    }
}

/// Parameters for searching visible message occurrences within one paginated thread.
public struct SearchThreadOccurrencesParams: Codable, Equatable, Sendable {
    public var threadId: ThreadId
    public var searchTerm: String
    public var cursor: String?
    public var pageSize: Int

    enum CodingKeys: String, CodingKey {
        case cursor
        case threadId = "thread_id"
        case searchTerm = "search_term"
        case pageSize = "page_size"
    }

    public init(threadId: ThreadId, searchTerm: String, cursor: String? = nil, pageSize: Int) {
        self.threadId = threadId
        self.searchTerm = searchTerm
        self.cursor = cursor
        self.pageSize = pageSize
    }
}

/// UTF-16 code-unit range within `snippet`.
public struct SearchTextRange: Codable, Equatable, Sendable {
    public var start: UInt32
    public var end: UInt32

    public init(start: UInt32, end: UInt32) {
        self.start = start
        self.end = end
    }
}

/// One visible message occurrence within a stored thread.
public struct StoredThreadOccurrence: Codable, Equatable, Sendable {
    public var turnId: String
    public var itemId: String
    public var snippet: String
    public var snippetMatchRange: SearchTextRange
    public var turnCursor: String

    enum CodingKeys: String, CodingKey {
        case snippet
        case turnId = "turn_id"
        case itemId = "item_id"
        case snippetMatchRange = "snippet_match_range"
        case turnCursor = "turn_cursor"
    }

    public init(
        turnId: String,
        itemId: String,
        snippet: String,
        snippetMatchRange: SearchTextRange,
        turnCursor: String
    ) {
        self.turnId = turnId
        self.itemId = itemId
        self.snippet = snippet
        self.snippetMatchRange = snippetMatchRange
        self.turnCursor = turnCursor
    }
}

/// A page of visible message occurrences within one stored thread.
public struct ThreadOccurrenceSearchPage: Codable, Sendable {
    public var items: [StoredThreadOccurrence]
    public var nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case items
        case nextCursor = "next_cursor"
    }

    public init(items: [StoredThreadOccurrence], nextCursor: String? = nil) {
        self.items = items
        self.nextCursor = nextCursor
    }
}

/// Store-owned thread metadata used by list/read/resume responses.
public struct StoredThread: Codable, Sendable {
    public var originator: String?
    public var threadId: ThreadId
    public var extraConfig: ExtraConfig?
    public var rolloutPath: String?
    public var forkedFromId: ThreadId?
    public var parentThreadId: ThreadId?
    public var preview: String
    public var name: String?
    public var modelProvider: String
    public var model: String?
    public var reasoningEffort: ReasoningEffort?
    public var createdAt: Date
    public var updatedAt: Date
    public var recencyAt: Date
    public var archivedAt: Date?
    public var section: ThreadSection?
    public var sectionPosition: Int64?
    public var sectionEnteredAt: Date?
    public var projectId: String?
    public var daybreakEnabled: Bool?
    public var cwd: String
    public var cliVersion: String
    public var source: SessionSource
    public var historyMode: ThreadHistoryMode
    public var threadSource: ThreadSource?
    public var agentNickname: String?
    public var agentRole: String?
    public var agentPath: String?
    public var gitInfo: GitInfo?
    public var approvalMode: AskForApproval
    public var permissionProfile: PermissionProfile
    public var tokenUsage: TokenUsage?
    public var firstUserMessage: String?
    public var history: StoredThreadHistory?

    enum CodingKeys: String, CodingKey {
        case originator, preview, name, model, cwd, source, history
        case threadId = "thread_id"
        case extraConfig = "extra_config"
        case rolloutPath = "rollout_path"
        case forkedFromId = "forked_from_id"
        case parentThreadId = "parent_thread_id"
        case modelProvider = "model_provider"
        case reasoningEffort = "reasoning_effort"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case recencyAt = "recency_at"
        case archivedAt = "archived_at"
        case section
        case sectionPosition = "section_position"
        case sectionEnteredAt = "section_entered_at"
        case projectId = "project_id"
        case daybreakEnabled = "daybreak_enabled"
        case cliVersion = "cli_version"
        case historyMode = "history_mode"
        case threadSource = "thread_source"
        case agentNickname = "agent_nickname"
        case agentRole = "agent_role"
        case agentPath = "agent_path"
        case gitInfo = "git_info"
        case approvalMode = "approval_mode"
        case permissionProfile = "permission_profile"
        case tokenUsage = "token_usage"
        case firstUserMessage = "first_user_message"
    }

    public init(
        originator: String? = nil,
        threadId: ThreadId,
        extraConfig: ExtraConfig? = nil,
        rolloutPath: String? = nil,
        forkedFromId: ThreadId? = nil,
        parentThreadId: ThreadId? = nil,
        preview: String,
        name: String? = nil,
        modelProvider: String,
        model: String? = nil,
        reasoningEffort: ReasoningEffort? = nil,
        createdAt: Date,
        updatedAt: Date,
        recencyAt: Date,
        archivedAt: Date? = nil,
        section: ThreadSection? = nil,
        sectionPosition: Int64? = nil,
        sectionEnteredAt: Date? = nil,
        projectId: String? = nil,
        daybreakEnabled: Bool? = nil,
        cwd: String,
        cliVersion: String,
        source: SessionSource,
        historyMode: ThreadHistoryMode,
        threadSource: ThreadSource? = nil,
        agentNickname: String? = nil,
        agentRole: String? = nil,
        agentPath: String? = nil,
        gitInfo: GitInfo? = nil,
        approvalMode: AskForApproval,
        permissionProfile: PermissionProfile,
        tokenUsage: TokenUsage? = nil,
        firstUserMessage: String? = nil,
        history: StoredThreadHistory? = nil
    ) {
        self.originator = originator
        self.threadId = threadId
        self.extraConfig = extraConfig
        self.rolloutPath = rolloutPath
        self.forkedFromId = forkedFromId
        self.parentThreadId = parentThreadId
        self.preview = preview
        self.name = name
        self.modelProvider = modelProvider
        self.model = model
        self.reasoningEffort = reasoningEffort
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.recencyAt = recencyAt
        self.archivedAt = archivedAt
        self.section = section
        self.sectionPosition = sectionPosition
        self.sectionEnteredAt = sectionEnteredAt
        self.projectId = projectId
        self.daybreakEnabled = daybreakEnabled
        self.cwd = cwd
        self.cliVersion = cliVersion
        self.source = source
        self.historyMode = historyMode
        self.threadSource = threadSource
        self.agentNickname = agentNickname
        self.agentRole = agentRole
        self.agentPath = agentPath
        self.gitInfo = gitInfo
        self.approvalMode = approvalMode
        self.permissionProfile = permissionProfile
        self.tokenUsage = tokenUsage
        self.firstUserMessage = firstUserMessage
        self.history = history
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        originator = try container.decodeIfPresent(String.self, forKey: .originator)
        threadId = try container.decode(ThreadId.self, forKey: .threadId)
        extraConfig = try container.decodeIfPresent(ExtraConfig.self, forKey: .extraConfig)
        rolloutPath = try container.decodeIfPresent(String.self, forKey: .rolloutPath)
        forkedFromId = try container.decodeIfPresent(ThreadId.self, forKey: .forkedFromId)
        parentThreadId = try container.decodeIfPresent(ThreadId.self, forKey: .parentThreadId)
        preview = try container.decode(String.self, forKey: .preview)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        modelProvider = try container.decode(String.self, forKey: .modelProvider)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        reasoningEffort = try container.decodeIfPresent(ReasoningEffort.self, forKey: .reasoningEffort)
        createdAt = try decodeDate(container, forKey: .createdAt)
        updatedAt = try decodeDate(container, forKey: .updatedAt)
        recencyAt = try decodeDate(container, forKey: .recencyAt)
        archivedAt = try decodeOptionalDate(container, forKey: .archivedAt)
        section = try container.decodeIfPresent(ThreadSection.self, forKey: .section)
        sectionPosition = try container.decodeIfPresent(Int64.self, forKey: .sectionPosition)
        sectionEnteredAt = try decodeOptionalDate(container, forKey: .sectionEnteredAt)
        projectId = try container.decodeIfPresent(String.self, forKey: .projectId)
        daybreakEnabled = try container.decodeIfPresent(Bool.self, forKey: .daybreakEnabled)
        cwd = try container.decode(String.self, forKey: .cwd)
        cliVersion = try container.decode(String.self, forKey: .cliVersion)
        source = try container.decode(SessionSource.self, forKey: .source)
        historyMode = try container.decode(ThreadHistoryMode.self, forKey: .historyMode)
        threadSource = try container.decodeIfPresent(ThreadSource.self, forKey: .threadSource)
        agentNickname = try container.decodeIfPresent(String.self, forKey: .agentNickname)
        agentRole = try container.decodeIfPresent(String.self, forKey: .agentRole)
        agentPath = try container.decodeIfPresent(String.self, forKey: .agentPath)
        gitInfo = try container.decodeIfPresent(GitInfo.self, forKey: .gitInfo)
        approvalMode = try container.decode(AskForApproval.self, forKey: .approvalMode)
        permissionProfile = try container.decode(PermissionProfile.self, forKey: .permissionProfile)
        tokenUsage = try container.decodeIfPresent(TokenUsage.self, forKey: .tokenUsage)
        firstUserMessage = try container.decodeIfPresent(String.self, forKey: .firstUserMessage)
        history = try container.decodeIfPresent(StoredThreadHistory.self, forKey: .history)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(originator, forKey: .originator)
        try container.encode(threadId, forKey: .threadId)
        try container.encodeIfPresent(extraConfig, forKey: .extraConfig)
        try container.encodeIfPresent(rolloutPath, forKey: .rolloutPath)
        try container.encodeIfPresent(forkedFromId, forKey: .forkedFromId)
        try container.encodeIfPresent(parentThreadId, forKey: .parentThreadId)
        try container.encode(preview, forKey: .preview)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encode(modelProvider, forKey: .modelProvider)
        try container.encodeIfPresent(model, forKey: .model)
        try container.encodeIfPresent(reasoningEffort, forKey: .reasoningEffort)
        try encodeDate(createdAt, forKey: .createdAt, into: &container)
        try encodeDate(updatedAt, forKey: .updatedAt, into: &container)
        try encodeDate(recencyAt, forKey: .recencyAt, into: &container)
        try encodeOptionalDate(archivedAt, forKey: .archivedAt, into: &container)
        try container.encodeIfPresent(section, forKey: .section)
        try container.encodeIfPresent(sectionPosition, forKey: .sectionPosition)
        try encodeOptionalDate(sectionEnteredAt, forKey: .sectionEnteredAt, into: &container)
        try container.encodeIfPresent(projectId, forKey: .projectId)
        try container.encodeIfPresent(daybreakEnabled, forKey: .daybreakEnabled)
        try container.encode(cwd, forKey: .cwd)
        try container.encode(cliVersion, forKey: .cliVersion)
        try container.encode(source, forKey: .source)
        try container.encode(historyMode, forKey: .historyMode)
        try container.encodeIfPresent(threadSource, forKey: .threadSource)
        try container.encodeIfPresent(agentNickname, forKey: .agentNickname)
        try container.encodeIfPresent(agentRole, forKey: .agentRole)
        try container.encodeIfPresent(agentPath, forKey: .agentPath)
        try container.encodeIfPresent(gitInfo, forKey: .gitInfo)
        try container.encode(approvalMode, forKey: .approvalMode)
        try container.encode(permissionProfile, forKey: .permissionProfile)
        try container.encodeIfPresent(tokenUsage, forKey: .tokenUsage)
        try container.encodeIfPresent(firstUserMessage, forKey: .firstUserMessage)
        try container.encodeIfPresent(history, forKey: .history)
    }
}

/// Patch for thread Git metadata.
public struct GitInfoPatch: Codable, Equatable, Sendable {
    public var sha: ClearableField<String>
    public var branch: ClearableField<String>
    public var originUrl: ClearableField<SanitizedGitUrl>

    enum CodingKeys: String, CodingKey {
        case sha, branch
        case originUrl = "origin_url"
    }

    public init(
        sha: ClearableField<String> = nil,
        branch: ClearableField<String> = nil,
        originUrl: ClearableField<SanitizedGitUrl> = nil
    ) {
        self.sha = sha
        self.branch = branch
        self.originUrl = originUrl
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sha = try decodeClearable(container, forKey: .sha)
        branch = try decodeClearable(container, forKey: .branch)
        originUrl = try decodeClearable(container, forKey: .originUrl)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try encodeClearable(sha, forKey: .sha, into: &container)
        try encodeClearable(branch, forKey: .branch, into: &container)
        try encodeClearable(originUrl, forKey: .originUrl, into: &container)
    }

    public mutating func merge(_ next: GitInfoPatch) {
        if next.sha != nil { sha = next.sha }
        if next.branch != nil { branch = next.branch }
        if next.originUrl != nil { originUrl = next.originUrl }
    }
}

/// Patch for thread metadata.
public struct ThreadMetadataPatch: Codable, Sendable {
    public var name: ClearableField<String>
    public var rolloutPath: String?
    public var preview: String?
    public var title: String?
    public var modelProvider: String?
    public var model: String?
    public var reasoningEffort: ClearableField<ReasoningEffort>
    public var createdAt: Date?
    public var updatedAt: Date?
    public var advanceRecencyAt: Date?
    public var source: SessionSource?
    public var creatorUserId: String?
    public var creatorAccountId: String?
    public var originator: String?
    public var threadSource: ClearableField<ThreadSource>
    public var agentNickname: ClearableField<String>
    public var agentRole: ClearableField<String>
    public var agentPath: ClearableField<String>
    public var cwd: String?
    public var cliVersion: String?
    public var approvalMode: AskForApproval?
    public var permissionProfile: PermissionProfile?
    public var tokenUsage: TokenUsage?
    public var firstUserMessage: String?
    public var gitInfo: GitInfoPatch?
    public var memoryMode: ThreadMemoryMode?
    public var projectId: ClearableField<String>
    public var daybreakEnabled: Bool?

    enum CodingKeys: String, CodingKey {
        case name, preview, title, model, source, originator, cwd
        case rolloutPath = "rollout_path"
        case modelProvider = "model_provider"
        case reasoningEffort = "reasoning_effort"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case advanceRecencyAt = "advance_recency_at"
        case creatorUserId = "creator_user_id"
        case creatorAccountId = "creator_account_id"
        case threadSource = "thread_source"
        case agentNickname = "agent_nickname"
        case agentRole = "agent_role"
        case agentPath = "agent_path"
        case cliVersion = "cli_version"
        case approvalMode = "approval_mode"
        case permissionProfile = "permission_profile"
        case tokenUsage = "token_usage"
        case firstUserMessage = "first_user_message"
        case gitInfo = "git_info"
        case memoryMode = "memory_mode"
        case projectId = "project_id"
        case daybreakEnabled = "daybreak_enabled"
    }

    public init(
        name: ClearableField<String> = nil,
        rolloutPath: String? = nil,
        preview: String? = nil,
        title: String? = nil,
        modelProvider: String? = nil,
        model: String? = nil,
        reasoningEffort: ClearableField<ReasoningEffort> = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil,
        advanceRecencyAt: Date? = nil,
        source: SessionSource? = nil,
        creatorUserId: String? = nil,
        creatorAccountId: String? = nil,
        originator: String? = nil,
        threadSource: ClearableField<ThreadSource> = nil,
        agentNickname: ClearableField<String> = nil,
        agentRole: ClearableField<String> = nil,
        agentPath: ClearableField<String> = nil,
        cwd: String? = nil,
        cliVersion: String? = nil,
        approvalMode: AskForApproval? = nil,
        permissionProfile: PermissionProfile? = nil,
        tokenUsage: TokenUsage? = nil,
        firstUserMessage: String? = nil,
        gitInfo: GitInfoPatch? = nil,
        memoryMode: ThreadMemoryMode? = nil,
        projectId: ClearableField<String> = nil,
        daybreakEnabled: Bool? = nil
    ) {
        self.name = name
        self.rolloutPath = rolloutPath
        self.preview = preview
        self.title = title
        self.modelProvider = modelProvider
        self.model = model
        self.reasoningEffort = reasoningEffort
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.advanceRecencyAt = advanceRecencyAt
        self.source = source
        self.creatorUserId = creatorUserId
        self.creatorAccountId = creatorAccountId
        self.originator = originator
        self.threadSource = threadSource
        self.agentNickname = agentNickname
        self.agentRole = agentRole
        self.agentPath = agentPath
        self.cwd = cwd
        self.cliVersion = cliVersion
        self.approvalMode = approvalMode
        self.permissionProfile = permissionProfile
        self.tokenUsage = tokenUsage
        self.firstUserMessage = firstUserMessage
        self.gitInfo = gitInfo
        self.memoryMode = memoryMode
        self.projectId = projectId
        self.daybreakEnabled = daybreakEnabled
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try decodeClearable(container, forKey: .name)
        rolloutPath = try container.decodeIfPresent(String.self, forKey: .rolloutPath)
        preview = try container.decodeIfPresent(String.self, forKey: .preview)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        modelProvider = try container.decodeIfPresent(String.self, forKey: .modelProvider)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        reasoningEffort = try decodeClearable(container, forKey: .reasoningEffort)
        createdAt = try decodeOptionalDate(container, forKey: .createdAt)
        updatedAt = try decodeOptionalDate(container, forKey: .updatedAt)
        advanceRecencyAt = try decodeOptionalDate(container, forKey: .advanceRecencyAt)
        source = try container.decodeIfPresent(SessionSource.self, forKey: .source)
        creatorUserId = try container.decodeIfPresent(String.self, forKey: .creatorUserId)
        creatorAccountId = try container.decodeIfPresent(String.self, forKey: .creatorAccountId)
        originator = try container.decodeIfPresent(String.self, forKey: .originator)
        threadSource = try decodeClearable(container, forKey: .threadSource)
        agentNickname = try decodeClearable(container, forKey: .agentNickname)
        agentRole = try decodeClearable(container, forKey: .agentRole)
        agentPath = try decodeClearable(container, forKey: .agentPath)
        cwd = try container.decodeIfPresent(String.self, forKey: .cwd)
        cliVersion = try container.decodeIfPresent(String.self, forKey: .cliVersion)
        approvalMode = try container.decodeIfPresent(AskForApproval.self, forKey: .approvalMode)
        permissionProfile = try container.decodeIfPresent(PermissionProfile.self, forKey: .permissionProfile)
        tokenUsage = try container.decodeIfPresent(TokenUsage.self, forKey: .tokenUsage)
        firstUserMessage = try container.decodeIfPresent(String.self, forKey: .firstUserMessage)
        gitInfo = try container.decodeIfPresent(GitInfoPatch.self, forKey: .gitInfo)
        memoryMode = try container.decodeIfPresent(ThreadMemoryMode.self, forKey: .memoryMode)
        projectId = try decodeClearable(container, forKey: .projectId)
        daybreakEnabled = try container.decodeIfPresent(Bool.self, forKey: .daybreakEnabled)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try encodeClearable(name, forKey: .name, into: &container)
        try container.encodeIfPresent(rolloutPath, forKey: .rolloutPath)
        try container.encodeIfPresent(preview, forKey: .preview)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(modelProvider, forKey: .modelProvider)
        try container.encodeIfPresent(model, forKey: .model)
        try encodeClearable(reasoningEffort, forKey: .reasoningEffort, into: &container)
        try encodeOptionalDate(createdAt, forKey: .createdAt, into: &container)
        try encodeOptionalDate(updatedAt, forKey: .updatedAt, into: &container)
        try encodeOptionalDate(advanceRecencyAt, forKey: .advanceRecencyAt, into: &container)
        try container.encodeIfPresent(source, forKey: .source)
        try container.encodeIfPresent(creatorUserId, forKey: .creatorUserId)
        try container.encodeIfPresent(creatorAccountId, forKey: .creatorAccountId)
        try container.encodeIfPresent(originator, forKey: .originator)
        try encodeClearable(threadSource, forKey: .threadSource, into: &container)
        try encodeClearable(agentNickname, forKey: .agentNickname, into: &container)
        try encodeClearable(agentRole, forKey: .agentRole, into: &container)
        try encodeClearable(agentPath, forKey: .agentPath, into: &container)
        try container.encodeIfPresent(cwd, forKey: .cwd)
        try container.encodeIfPresent(cliVersion, forKey: .cliVersion)
        try container.encodeIfPresent(approvalMode, forKey: .approvalMode)
        try container.encodeIfPresent(permissionProfile, forKey: .permissionProfile)
        try container.encodeIfPresent(tokenUsage, forKey: .tokenUsage)
        try container.encodeIfPresent(firstUserMessage, forKey: .firstUserMessage)
        try container.encodeIfPresent(gitInfo, forKey: .gitInfo)
        try container.encodeIfPresent(memoryMode, forKey: .memoryMode)
        try encodeClearable(projectId, forKey: .projectId, into: &container)
        try container.encodeIfPresent(daybreakEnabled, forKey: .daybreakEnabled)
    }

    public mutating func merge(_ next: ThreadMetadataPatch) {
        if next.name != nil { name = next.name }
        if next.rolloutPath != nil { rolloutPath = next.rolloutPath }
        if next.preview != nil { preview = next.preview }
        if next.title != nil { title = next.title }
        if next.modelProvider != nil { modelProvider = next.modelProvider }
        if next.model != nil { model = next.model }
        if next.reasoningEffort != nil { reasoningEffort = next.reasoningEffort }
        if next.createdAt != nil { createdAt = next.createdAt }
        if next.updatedAt != nil { updatedAt = next.updatedAt }
        if next.advanceRecencyAt != nil { advanceRecencyAt = next.advanceRecencyAt }
        if next.source != nil { source = next.source }
        if next.creatorUserId != nil { creatorUserId = next.creatorUserId }
        if next.creatorAccountId != nil { creatorAccountId = next.creatorAccountId }
        if next.originator != nil { originator = next.originator }
        if next.threadSource != nil { threadSource = next.threadSource }
        if next.agentNickname != nil { agentNickname = next.agentNickname }
        if next.agentRole != nil { agentRole = next.agentRole }
        if next.agentPath != nil { agentPath = next.agentPath }
        if next.cwd != nil { cwd = next.cwd }
        if next.cliVersion != nil { cliVersion = next.cliVersion }
        if next.approvalMode != nil { approvalMode = next.approvalMode }
        if next.permissionProfile != nil { permissionProfile = next.permissionProfile }
        if next.tokenUsage != nil { tokenUsage = next.tokenUsage }
        if next.firstUserMessage != nil { firstUserMessage = next.firstUserMessage }
        if let gitInfo = next.gitInfo {
            var current = self.gitInfo ?? GitInfoPatch()
            current.merge(gitInfo)
            self.gitInfo = current
        }
        if next.memoryMode != nil { memoryMode = next.memoryMode }
        if next.projectId != nil { projectId = next.projectId }
        if next.daybreakEnabled != nil { daybreakEnabled = next.daybreakEnabled }
    }

    public func isEmpty() -> Bool {
        name == nil
            && rolloutPath == nil
            && preview == nil
            && title == nil
            && modelProvider == nil
            && model == nil
            && reasoningEffort == nil
            && createdAt == nil
            && updatedAt == nil
            && advanceRecencyAt == nil
            && source == nil
            && originator == nil
            && creatorUserId == nil
            && creatorAccountId == nil
            && threadSource == nil
            && agentNickname == nil
            && agentRole == nil
            && agentPath == nil
            && cwd == nil
            && cliVersion == nil
            && approvalMode == nil
            && permissionProfile == nil
            && tokenUsage == nil
            && firstUserMessage == nil
            && gitInfo == nil
            && memoryMode == nil
            && projectId == nil
            && daybreakEnabled == nil
    }
}

/// Parameters for patching mutable thread metadata.
public struct UpdateThreadMetadataParams: Codable, Sendable {
    public var threadId: ThreadId
    public var patch: ThreadMetadataPatch
    public var includeArchived: Bool

    enum CodingKeys: String, CodingKey {
        case patch
        case threadId = "thread_id"
        case includeArchived = "include_archived"
    }

    public init(threadId: ThreadId, patch: ThreadMetadataPatch, includeArchived: Bool) {
        self.threadId = threadId
        self.patch = patch
        self.includeArchived = includeArchived
    }
}

/// Parameters for moving a thread to, within, or out of a server-ordered section.
public struct MoveThreadToSectionParams: Codable, Equatable, Sendable {
    public var threadId: ThreadId
    public var section: String?
    public var beforeThreadId: ThreadId?

    enum CodingKeys: String, CodingKey {
        case section
        case threadId = "thread_id"
        case beforeThreadId = "before_thread_id"
    }

    public init(threadId: ThreadId, section: String?, beforeThreadId: ThreadId? = nil) {
        self.threadId = threadId
        self.section = section
        self.beforeThreadId = beforeThreadId
    }
}

/// Parameters for archiving or unarchiving a thread.
public struct ArchiveThreadParams: Codable, Equatable, Sendable {
    public var threadId: ThreadId

    enum CodingKeys: String, CodingKey { case threadId = "thread_id" }

    public init(threadId: ThreadId) {
        self.threadId = threadId
    }
}

/// Parameters for archiving a set of threads as one store operation.
public struct ArchiveThreadsParams: Codable, Equatable, Sendable {
    public var threadIds: [ThreadId]
    public var writerLockThreadIds: [ThreadId]

    enum CodingKeys: String, CodingKey {
        case threadIds = "thread_ids"
        case writerLockThreadIds = "writer_lock_thread_ids"
    }

    public init(threadIds: [ThreadId], writerLockThreadIds: [ThreadId] = []) {
        self.threadIds = threadIds
        self.writerLockThreadIds = writerLockThreadIds
    }
}

/// Parameters for deleting a thread.
public struct DeleteThreadParams: Codable, Equatable, Sendable {
    public var threadId: ThreadId

    enum CodingKeys: String, CodingKey { case threadId = "thread_id" }

    public init(threadId: ThreadId) {
        self.threadId = threadId
    }
}

/// Parameters for deleting a set of threads as one store operation.
public struct DeleteThreadsParams: Codable, Equatable, Sendable {
    public var threadIds: [ThreadId]

    enum CodingKeys: String, CodingKey { case threadIds = "thread_ids" }

    public init(threadIds: [ThreadId]) {
        self.threadIds = threadIds
    }
}

// MARK: - Codable helpers

func decodeClearable<T: Decodable, K: CodingKey>(
    _ container: KeyedDecodingContainer<K>,
    forKey key: K
) throws -> ClearableField<T> {
    guard container.contains(key) else { return nil }
    if try container.decodeNil(forKey: key) { return .some(nil) }
    return .some(try container.decode(T.self, forKey: key))
}

func encodeClearable<T: Encodable, K: CodingKey>(
    _ value: ClearableField<T>,
    forKey key: K,
    into container: inout KeyedEncodingContainer<K>
) throws {
    switch value {
    case .none:
        break
    case .some(.none):
        try container.encodeNil(forKey: key)
    case .some(.some(let inner)):
        try container.encode(inner, forKey: key)
    }
}

func decodeDate<K: CodingKey>(_ container: KeyedDecodingContainer<K>, forKey key: K) throws -> Date {
    try threadStoreDecodeDate(try container.decode(String.self, forKey: key))
}

func decodeOptionalDate<K: CodingKey>(
    _ container: KeyedDecodingContainer<K>,
    forKey key: K
) throws -> Date? {
    guard let raw = try container.decodeIfPresent(String.self, forKey: key) else { return nil }
    return try threadStoreDecodeDate(raw)
}

func encodeDate<K: CodingKey>(
    _ date: Date,
    forKey key: K,
    into container: inout KeyedEncodingContainer<K>
) throws {
    try container.encode(threadStoreEncodeDate(date), forKey: key)
}

func encodeOptionalDate<K: CodingKey>(
    _ date: Date?,
    forKey key: K,
    into container: inout KeyedEncodingContainer<K>
) throws {
    guard let date else { return }
    try encodeDate(date, forKey: key, into: &container)
}

private let threadStoreDateFrac: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    return formatter
}()

private let threadStoreDatePlain: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    return formatter
}()

func threadStoreEncodeDate(_ date: Date) -> String {
    threadStoreDateFrac.string(from: date)
}

func threadStoreDecodeDate(_ string: String) throws -> Date {
    if let date = threadStoreDateFrac.date(from: string) ?? threadStoreDatePlain.date(from: string) {
        return date
    }
    throw DecodingError.dataCorrupted(
        DecodingError.Context(
            codingPath: [],
            debugDescription: "invalid RFC 3339 timestamp: \(string)"))
}
