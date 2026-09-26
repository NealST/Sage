//
//  in_memory.swift
//  CodexThreadStore
//
//  Port of codex-rs/thread-store/src/in_memory.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  `tokio::sync::Mutex` / process-wide `OnceLock` map to
//  `OSAllocatedUnfairLock`. `state_db` cleanup is omitted (GRDB later).
//  Projects, independently persisted sections, and attachments are stored
//  in memory here (Rust leaves those trait methods unsupported).
//

import CodexHistory
import CodexProtocol
import CodexRollout
import Foundation
import os

private let inMemoryThreadStores = OSAllocatedUnfairLock<[String: InMemoryThreadStore]>(initialState: [:])

/// Recorded call counts for `InMemoryThreadStore`.
public struct InMemoryThreadStoreCalls: Equatable, Sendable {
    public var createThread: Int = 0
    public var resumeThread: Int = 0
    public var appendItems: Int = 0
    public var persistThread: Int = 0
    public var flushThread: Int = 0
    public var shutdownThread: Int = 0
    public var discardThread: Int = 0
    public var loadHistory: Int = 0
    public var loadLatestModelContext: Int = 0
    public var readThread: Int = 0
    public var readThreadWithHistory: Int = 0
    public var readThreadByRolloutPath: Int = 0
    public var listThreads: Int = 0
    public var updateThreadMetadata: Int = 0
    public var archiveThread: Int = 0
    public var unarchiveThread: Int = 0
    public var deleteThread: Int = 0

    public init() {}
}

private struct InMemoryThreadStoreState {
    var calls = InMemoryThreadStoreCalls()
    var createdThreads: [ThreadId: CreateThreadParams] = [:]
    var histories: [ThreadId: [RolloutItem]] = [:]
    var metadataUpdates: [ThreadId: ThreadMetadataPatch] = [:]
    var sections: [ThreadId: String] = [:]
    var sectionPositions: [ThreadId: Int64] = [:]
    var sectionEnteredAt: [ThreadId: Date] = [:]
    var names: [ThreadId: String?] = [:]
    var projectIds: [ThreadId: String] = [:]
    var rolloutPaths: [String: ThreadId] = [:]
    var archived: Set<ThreadId> = []
    var sectionCatalog: [String: StoredThreadSection] = [
        PINNED_THREAD_SECTION_ID: StoredThreadSection(
            id: PINNED_THREAD_SECTION_ID,
            name: PINNED_THREAD_SECTION_NAME)
    ]
    var projects: [String: StoredProject] = [:]
    var projectIdempotency: [String: String] = [:]
    var attachments: [ThreadId: [ThreadAttachment]] = [:]
}

/// In-memory `ThreadStore` implementation for tests and debug configs.
public final class InMemoryThreadStore: ThreadStore, @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: InMemoryThreadStoreState())
    private let omitMetadataUpdateResult = OSAllocatedUnfairLock(initialState: false)

    public init() {}

    /// Returns the store associated with `id`, creating it if needed.
    public static func forId(_ id: String) -> InMemoryThreadStore {
        inMemoryThreadStores.withLock { stores in
            if let existing = stores[id] { return existing }
            let created = InMemoryThreadStore()
            stores[id] = created
            return created
        }
    }

    /// Removes a shared in-memory store for `id`.
    public static func removeId(_ id: String) -> InMemoryThreadStore? {
        inMemoryThreadStores.withLock { $0.removeValue(forKey: id) }
    }

    /// Shares this debug store's thread data. The GRDB handle is ignored until local/ lands.
    public func withStateDb(_ stateDb: StateDbHandle?) -> InMemoryThreadStore {
        _ = stateDb
        return self
    }

    public func calls() -> InMemoryThreadStoreCalls {
        lock.withLock { $0.calls }
    }

    /// Makes metadata updates apply normally while returning no materialized thread.
    public func omitMetadataUpdateResultForTesting() {
        omitMetadataUpdateResult.withLock { $0 = true }
    }

    public func defaultHistoryMode() -> ThreadHistoryMode { .legacy }

    public func createThread(_ params: CreateThreadParams) async throws {
        lock.withLock { state in
            state.calls.createThread += 1
            var sessionMeta = SessionMeta(
                sessionId: params.sessionId,
                id: params.threadId,
                cwd: params.metadata.cwd ?? "",
                originator: params.originator,
                source: params.source)
            sessionMeta.forkedFromId = params.forkedFromId
            sessionMeta.parentThreadId = params.parentThreadId
            sessionMeta.runtimeWorkspaceRoots = params.runtimeWorkspaceRoots
            sessionMeta.agentNickname = sessionSourceNickname(params.source)
            sessionMeta.agentRole = sessionSourceAgentRole(params.source)
            sessionMeta.agentPath = sessionSourceAgentPath(params.source)
            sessionMeta.creatorUserId = params.creatorUserId
            sessionMeta.creatorAccountId = params.creatorAccountId
            sessionMeta.threadSource = params.threadSource
            sessionMeta.modelProvider = params.metadata.modelProvider
            sessionMeta.baseInstructions = params.baseInstructions
            sessionMeta.dynamicTools = params.dynamicTools.isEmpty ? nil : params.dynamicTools
            sessionMeta.selectedCapabilityRoots = params.selectedCapabilityRoots
            sessionMeta.memoryMode = params.metadata.memoryMode == .disabled ? "disabled" : nil
            sessionMeta.historyMode = params.historyMode
            sessionMeta.historyBase = params.historyBase
            sessionMeta.subagentHistoryStartOrdinal = params.subagentHistoryStartOrdinal
            sessionMeta.multiAgentVersion = params.multiAgentVersion
            sessionMeta.contextWindow = SessionContextWindow(windowId: params.initialWindowId)
            state.histories[params.threadId, default: []].append(
                .sessionMeta(SessionMetaLine(meta: sessionMeta, git: nil)))
            state.createdThreads[params.threadId] = params
        }
    }

    public func resumeThread(_ params: ResumeThreadParams) async throws {
        lock.withLock { state in
            state.calls.resumeThread += 1
            if let history = params.history {
                state.histories[params.threadId] = history
            } else {
                state.histories[params.threadId] = state.histories[params.threadId] ?? []
            }
            if let rolloutPath = params.rolloutPath {
                state.rolloutPaths[rolloutPath] = params.threadId
            }
        }
    }

    public func appendItems(_ params: AppendThreadItemsParams) async throws {
        if params.items.isEmpty { return }
        lock.withLock { state in
            let historyMode = historyModeFromState(state, params.threadId)
            let persisted = persistedRolloutItems(params.items, historyMode: historyMode)
            if persisted.isEmpty { return }
            state.calls.appendItems += 1
            state.histories[params.threadId, default: []].append(contentsOf: persisted)
        }
    }

    public func persistThread(threadId: ThreadId, context: PersistContext) async throws {
        _ = threadId
        _ = context
        lock.withLock { $0.calls.persistThread += 1 }
    }

    public func flushThread(threadId: ThreadId) async throws {
        _ = threadId
        lock.withLock { $0.calls.flushThread += 1 }
    }

    public func shutdownThread(threadId: ThreadId) async throws {
        _ = threadId
        lock.withLock { $0.calls.shutdownThread += 1 }
    }

    public func discardThread(threadId: ThreadId) async throws {
        _ = threadId
        lock.withLock { $0.calls.discardThread += 1 }
    }

    public func loadHistory(_ params: LoadThreadHistoryParams) async throws -> StoredThreadHistory {
        try lock.withLock { state in
            state.calls.loadHistory += 1
            guard let items = state.histories[params.threadId] else {
                throw ThreadStoreError.threadNotFound(params.threadId.description)
            }
            try rejectPaginatedHistoryMode(historyModeFromState(state, params.threadId))
            return StoredThreadHistory(threadId: params.threadId, items: items)
        }
    }

    public func loadLatestModelContext(
        _ params: LoadThreadHistoryParams
    ) async throws -> StoredModelContext {
        try lock.withLock { state in
            state.calls.loadLatestModelContext += 1
            guard let items = state.histories[params.threadId] else {
                throw ThreadStoreError.threadNotFound(params.threadId.description)
            }
            return StoredModelContext(threadId: params.threadId, items: items)
        }
    }

    public func readThread(_ params: ReadThreadParams) async throws -> StoredThread {
        try lock.withLock { state in
            state.calls.readThread += 1
            if params.includeHistory {
                state.calls.readThreadWithHistory += 1
                try rejectPaginatedHistoryMode(historyModeFromState(state, params.threadId))
            }
            return try storedThreadFromState(state, params.threadId, includeHistory: params.includeHistory)
        }
    }

    public func readThreadByRolloutPath(
        _ params: ReadThreadByRolloutPathParams
    ) async throws -> StoredThread {
        try lock.withLock { state in
            state.calls.readThreadByRolloutPath += 1
            guard let threadId = state.rolloutPaths[params.rolloutPath] else {
                throw ThreadStoreError.invalidRequest(
                    "in-memory thread store does not know rollout path \(params.rolloutPath)")
            }
            if params.includeHistory {
                try rejectPaginatedHistoryMode(historyModeFromState(state, threadId))
            }
            return try storedThreadFromState(state, threadId, includeHistory: params.includeHistory)
        }
    }

    public func listThreads(_ params: ListThreadsParams) async throws -> ThreadPage {
        try lock.withLock { state in
            state.calls.listThreads += 1
            var items = try state.createdThreads.keys.map { threadId in
                try storedThreadFromState(state, threadId, includeHistory: false)
            }
            items.sort { $0.threadId.description < $1.threadId.description }

            switch params.relationFilter {
            case .directChildrenOf(let parentThreadId):
                items.removeAll { $0.parentThreadId != parentThreadId }
            case .descendantsOf(let ancestorThreadId):
                var subtree: Set<ThreadId> = [ancestorThreadId]
                var discovered = true
                while discovered {
                    discovered = false
                    for thread in items {
                        if let parent = thread.parentThreadId, subtree.contains(parent) {
                            discovered = subtree.insert(thread.threadId).inserted || discovered
                        }
                    }
                }
                items.removeAll {
                    $0.threadId == ancestorThreadId || !subtree.contains($0.threadId)
                }
            case nil:
                break
            }

            switch params.section {
            case .none:
                break
            case .some(let wanted):
                items.removeAll { $0.section?.id != wanted }
            }
            switch params.projectId {
            case .none:
                break
            case .some(let wanted):
                items.removeAll { $0.projectId != wanted }
            }
            if !params.allowedSources.isEmpty {
                items.removeAll { !params.allowedSources.contains($0.source) }
            }
            if let providers = params.modelProviders, !providers.isEmpty {
                items.removeAll { !providers.contains($0.modelProvider) }
            }
            if let cwdFilters = params.cwdFilters {
                items.removeAll { !cwdFilters.contains($0.cwd) }
            }
            if let term = params.searchTerm?.lowercased(), !term.isEmpty {
                items.removeAll { thread in
                    !(thread.name?.lowercased().contains(term) == true
                        || thread.preview.lowercased().contains(term))
                }
            }
            items.removeAll { thread in
                params.archived != state.archived.contains(thread.threadId)
            }

            if params.sortKey == .sectionPosition {
                items.sort {
                    ($0.sectionPosition ?? Int64.max, $0.threadId.description)
                        < ($1.sectionPosition ?? Int64.max, $1.threadId.description)
                }
                if params.sortDirection == .desc { items.reverse() }
            }

            return ThreadPage(items: items, nextCursor: nil)
        }
    }

    public func updateThreadMetadata(_ params: UpdateThreadMetadataParams) async throws -> StoredThread? {
        let updated: StoredThread = try lock.withLock { state in
            if params.patch.projectId != nil {
                throw ThreadStoreError.unsupported(operation: "projects")
            }
            state.calls.updateThreadMetadata += 1
            guard state.createdThreads[params.threadId] != nil else {
                throw ThreadStoreError.threadNotFound(params.threadId.description)
            }
            if let name = params.patch.name {
                state.names[params.threadId] = name
            }
            var merged = state.metadataUpdates[params.threadId] ?? ThreadMetadataPatch()
            merged.merge(params.patch)
            state.metadataUpdates[params.threadId] = merged
            return try storedThreadFromState(state, params.threadId, includeHistory: false)
        }
        if omitMetadataUpdateResult.withLock({ $0 }) { return nil }
        return updated
    }

    public func moveThreadToSection(_ params: MoveThreadToSectionParams) async throws {
        try lock.withLock { state in
            if let section = params.section, section.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw ThreadStoreError.invalidRequest("section must not be empty")
            }
            if params.section == nil && params.beforeThreadId != nil {
                throw ThreadStoreError.invalidRequest(
                    "before thread cannot be specified without a section")
            }
            guard state.createdThreads[params.threadId] != nil else {
                throw ThreadStoreError.threadNotFound(params.threadId.description)
            }
            let previousSection = state.sections[params.threadId]
            guard let section = params.section else {
                state.sections.removeValue(forKey: params.threadId)
                state.sectionPositions.removeValue(forKey: params.threadId)
                state.sectionEnteredAt.removeValue(forKey: params.threadId)
                return
            }
            if let beforeThreadId = params.beforeThreadId {
                if beforeThreadId == params.threadId {
                    throw ThreadStoreError.invalidRequest(
                        "thread \(params.threadId) cannot be moved before itself")
                }
                if state.sections[beforeThreadId] != section {
                    throw ThreadStoreError.invalidRequest(
                        "before thread \(beforeThreadId) is not in section \(section)")
                }
            }
            var ordered = state.sections.compactMap { threadId, current -> ThreadId? in
                threadId != params.threadId && current == section ? threadId : nil
            }
            ordered.sort {
                (state.sectionPositions[$0] ?? Int64.max, $0.description)
                    < (state.sectionPositions[$1] ?? Int64.max, $1.description)
            }
            let insertAt = params.beforeThreadId.flatMap { before in
                ordered.firstIndex(of: before)
            } ?? ordered.count
            ordered.insert(params.threadId, at: insertAt)
            for (index, threadId) in ordered.enumerated() {
                let position = (Int64(index) &+ 1) &* 1_000_000
                state.sectionPositions[threadId] = position
            }
            if previousSection != section {
                state.sectionEnteredAt[params.threadId] = Date()
                state.sections[params.threadId] = section
            }
        }
    }

    public func archiveThread(_ params: ArchiveThreadParams) async throws {
        lock.withLock { state in
            state.calls.archiveThread += 1
            state.archived.insert(params.threadId)
        }
    }

    public func unarchiveThread(_ params: ArchiveThreadParams) async throws -> StoredThread {
        try lock.withLock { state in
            state.calls.unarchiveThread += 1
            state.archived.remove(params.threadId)
            return try storedThreadFromState(state, params.threadId, includeHistory: false)
        }
    }

    public func deleteThread(_ params: DeleteThreadParams) async throws {
        try lock.withLock { state in
            state.calls.deleteThread += 1
            let existed = state.histories.removeValue(forKey: params.threadId) != nil
            state.createdThreads.removeValue(forKey: params.threadId)
            state.names.removeValue(forKey: params.threadId)
            state.metadataUpdates.removeValue(forKey: params.threadId)
            state.sections.removeValue(forKey: params.threadId)
            state.sectionPositions.removeValue(forKey: params.threadId)
            state.sectionEnteredAt.removeValue(forKey: params.threadId)
            state.projectIds.removeValue(forKey: params.threadId)
            state.attachments.removeValue(forKey: params.threadId)
            state.archived.remove(params.threadId)
            state.rolloutPaths = state.rolloutPaths.filter { $0.value != params.threadId }
            if !existed {
                throw ThreadStoreError.threadNotFound(params.threadId.description)
            }
        }
    }

    public func supportsThreadSections() -> Bool { true }

    public func listThreadSections(
        _ params: ListThreadSectionsParams
    ) async throws -> StoredThreadSectionsPage {
        lock.withLock { state in
            var sections = Array(state.sectionCatalog.values)
            sections.sort { $0.id < $1.id }
            if let cursor = params.cursor {
                sections = Array(sections.drop(while: { $0.id <= cursor }))
            }
            let limit = max(params.limit, 0)
            let nextCursor = limit > 0 && sections.count > limit ? sections[limit - 1].id : nil
            if limit == 0 {
                sections = []
            } else if sections.count > limit {
                sections = Array(sections.prefix(limit))
            }
            return StoredThreadSectionsPage(sections: sections, nextCursor: nextCursor)
        }
    }

    public func createThreadSection(
        _ params: CreateThreadSectionParams
    ) async throws -> StoredThreadSection {
        try lock.withLock { state in
            let name = params.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty {
                throw ThreadStoreError.invalidRequest("section name must not be empty")
            }
            let section = StoredThreadSection(
                id: ThreadId().description,
                name: name,
                appearance: params.appearance)
            state.sectionCatalog[section.id] = section
            return section
        }
    }

    public func renameThreadSection(
        _ params: RenameThreadSectionParams
    ) async throws -> StoredThreadSection? {
        try lock.withLock { state in
            if params.sectionId == PINNED_THREAD_SECTION_ID {
                throw ThreadStoreError.invalidRequest("cannot rename the pinned section")
            }
            guard var section = state.sectionCatalog[params.sectionId] else { return nil }
            let name = params.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty {
                throw ThreadStoreError.invalidRequest("section name must not be empty")
            }
            section.name = name
            if let appearance = params.appearance {
                section.appearance = appearance
            }
            state.sectionCatalog[params.sectionId] = section
            return section
        }
    }

    public func deleteThreadSection(_ params: DeleteThreadSectionParams) async throws -> Bool {
        try lock.withLock { state in
            if params.sectionId == PINNED_THREAD_SECTION_ID {
                throw ThreadStoreError.invalidRequest("cannot delete the pinned section")
            }
            guard state.sectionCatalog.removeValue(forKey: params.sectionId) != nil else {
                return false
            }
            let members = state.sections.compactMap { threadId, section in
                section == params.sectionId ? threadId : nil
            }
            for threadId in members {
                state.sections.removeValue(forKey: threadId)
                state.sectionPositions.removeValue(forKey: threadId)
                state.sectionEnteredAt.removeValue(forKey: threadId)
            }
            return true
        }
    }

    public func supportsThreadAttachments() -> Bool { true }

    public func copyThreadAttachments(
        sourceThreadId: ThreadId,
        destinationThreadId: ThreadId
    ) async throws {
        try lock.withLock { state in
            guard state.createdThreads[sourceThreadId] != nil else {
                throw ThreadStoreError.threadNotFound(sourceThreadId.description)
            }
            guard state.createdThreads[destinationThreadId] != nil else {
                throw ThreadStoreError.threadNotFound(destinationThreadId.description)
            }
            if let existing = state.attachments[destinationThreadId], !existing.isEmpty {
                throw ThreadStoreError.invalidRequest("destination thread already has attachments")
            }
            let copies = (state.attachments[sourceThreadId] ?? []).map { attachment in
                ThreadAttachment(
                    id: ThreadId().description,
                    threadId: destinationThreadId,
                    attachmentType: attachment.attachmentType,
                    identityKey: attachment.identityKey,
                    payload: attachment.payload,
                    createdAt: Int64(Date().timeIntervalSince1970))
            }
            state.attachments[destinationThreadId] = copies
        }
    }

    public func addThreadAttachment(
        _ params: AddThreadAttachmentParams
    ) async throws -> AddThreadAttachmentOutcome {
        try lock.withLock { state in
            guard state.createdThreads[params.threadId] != nil else {
                throw ThreadStoreError.threadNotFound(params.threadId.description)
            }
            if params.attachmentType.utf8.count > MAX_THREAD_ATTACHMENT_TYPE_BYTES
                || params.identityKey.utf8.count > MAX_THREAD_ATTACHMENT_IDENTITY_KEY_BYTES {
                throw ThreadStoreError.invalidRequest("attachment identity exceeds size limits")
            }
            let payloadBytes = (try? JSONEncoder().encode(params.payload))?.count ?? 0
            if payloadBytes > MAX_THREAD_ATTACHMENT_PAYLOAD_BYTES {
                throw ThreadStoreError.invalidRequest("attachment payload exceeds size limits")
            }
            var list = state.attachments[params.threadId] ?? []
            if let existing = list.first(where: {
                $0.attachmentType == params.attachmentType && $0.identityKey == params.identityKey
            }) {
                return .existing(existing)
            }
            if list.count >= MAX_THREAD_ATTACHMENTS_PER_THREAD {
                throw ThreadStoreError.invalidRequest("thread already has the maximum number of attachments")
            }
            let attachment = ThreadAttachment(
                id: ThreadId().description,
                threadId: params.threadId,
                attachmentType: params.attachmentType,
                identityKey: params.identityKey,
                payload: params.payload,
                createdAt: Int64(Date().timeIntervalSince1970))
            list.append(attachment)
            state.attachments[params.threadId] = list
            return .created(attachment)
        }
    }

    public func listThreadAttachments(
        _ params: ListThreadAttachmentsParams
    ) async throws -> ThreadAttachmentPage {
        try lock.withLock { state in
            guard state.createdThreads[params.threadId] != nil else {
                throw ThreadStoreError.threadNotFound(params.threadId.description)
            }
            var attachments = state.attachments[params.threadId] ?? []
            attachments.sort {
                ($0.createdAt, $0.id) < ($1.createdAt, $1.id)
            }
            if let cursor = params.cursor {
                attachments = Array(attachments.drop(while: { $0.id != cursor }).dropFirst())
            }
            let limit = min(max(params.limit, 0), MAX_THREAD_ATTACHMENT_LIST_PAGE_SIZE)
            let nextCursor = limit > 0 && attachments.count > limit ? attachments[limit - 1].id : nil
            if limit == 0 {
                attachments = []
            } else if attachments.count > limit {
                attachments = Array(attachments.prefix(limit))
            }
            return ThreadAttachmentPage(attachments: attachments, nextCursor: nextCursor)
        }
    }

    public func removeThreadAttachment(
        _ params: RemoveThreadAttachmentParams
    ) async throws -> RemoveThreadAttachmentOutcome {
        try lock.withLock { state in
            guard state.createdThreads[params.threadId] != nil else {
                throw ThreadStoreError.threadNotFound(params.threadId.description)
            }
            guard var list = state.attachments[params.threadId],
                  let index = list.firstIndex(where: {
                      $0.attachmentType == params.attachmentType && $0.identityKey == params.identityKey
                  }) else {
                return .notFound
            }
            let removed = list.remove(at: index)
            state.attachments[params.threadId] = list
            return .removed(removed)
        }
    }

    public func supportsProjects() -> Bool { true }

    public func listProjects(_ params: ListProjectsParams) async throws -> StoredProjectsPage {
        lock.withLock { state in
            var projects = Array(state.projects.values)
            switch params.sortKey {
            case .position:
                projects.sort { ($0.position, $0.id) < ($1.position, $1.id) }
            case .recencyAt:
                projects.sort {
                    ($0.recencyAtMs ?? $0.updatedAtMs, $0.id) < ($1.recencyAtMs ?? $1.updatedAtMs, $1.id)
                }
            }
            if params.sortDirection == .desc { projects.reverse() }
            if let cursor = params.cursor, let index = projects.firstIndex(where: { $0.id == cursor }) {
                projects = Array(projects.suffix(from: index + 1))
            }
            let limit = max(params.limit, 0)
            let nextCursor = limit > 0 && projects.count > limit ? projects[limit - 1].id : nil
            if limit == 0 {
                projects = []
            } else if projects.count > limit {
                projects = Array(projects.prefix(limit))
            }
            return StoredProjectsPage(projects: projects, nextCursor: nextCursor)
        }
    }

    public func readProject(projectId: String) async throws -> StoredProject? {
        lock.withLock { $0.projects[projectId] }
    }

    public func createProject(_ params: CreateProjectParams) async throws -> CreatedProject {
        lock.withLock { state in
            if let existingId = state.projectIdempotency[params.idempotencyKey],
               let existing = state.projects[existingId] {
                return CreatedProject(project: existing, created: false)
            }
            let now = Int64(Date().timeIntervalSince1970 * 1000)
            let position = (state.projects.values.map(\.position).max() ?? 0) + 1_000_000
            let project = StoredProject(
                id: ThreadId().description,
                name: params.name,
                roots: params.roots,
                metadata: params.metadata,
                position: position,
                createdAtMs: now,
                updatedAtMs: now)
            state.projects[project.id] = project
            state.projectIdempotency[params.idempotencyKey] = project.id
            for threadIdString in params.threadIds {
                if let threadId = try? ThreadId.fromString(threadIdString),
                   state.createdThreads[threadId] != nil {
                    state.projectIds[threadId] = project.id
                }
            }
            return CreatedProject(project: project, created: true)
        }
    }

    public func updateProject(_ params: UpdateProjectParams) async throws -> UpdatedProject? {
        lock.withLock { state in
            guard var project = state.projects[params.projectId] else { return nil }
            var changed = false
            if let name = params.name, name != project.name {
                project.name = name
                changed = true
            }
            if let roots = params.roots, roots != project.roots {
                project.roots = roots
                changed = true
            }
            if let metadata = params.metadata, metadata != project.metadata {
                project.metadata = metadata
                changed = true
            }
            if changed {
                project.updatedAtMs = Int64(Date().timeIntervalSince1970 * 1000)
                state.projects[params.projectId] = project
            }
            return UpdatedProject(project: project, changed: changed)
        }
    }

    public func moveProject(_ params: MoveProjectParams) async throws -> ProjectMoveOutcome? {
        try lock.withLock { state in
            guard state.projects[params.projectId] != nil else { return nil }
            var ordered = Array(state.projects.values)
            ordered.sort { ($0.position, $0.id) < ($1.position, $1.id) }
            guard let from = ordered.firstIndex(where: { $0.id == params.projectId }) else {
                return .unchanged
            }
            if let before = params.beforeProjectId {
                guard ordered.contains(where: { $0.id == before }) else {
                    throw ThreadStoreError.invalidRequest(
                        "before project \(before) does not exist")
                }
                if before == params.projectId { return .unchanged }
            }
            let moving = ordered.remove(at: from)
            let insertAt = params.beforeProjectId.flatMap { before in
                ordered.firstIndex(where: { $0.id == before })
            } ?? ordered.count
            ordered.insert(moving, at: insertAt)
            for (index, project) in ordered.enumerated() {
                var updated = project
                updated.position = (Int64(index) &+ 1) &* 1_000_000
                state.projects[project.id] = updated
            }
            return .moved
        }
    }

    public func deleteProject(projectId: String) async throws -> DeletedProject? {
        lock.withLock { state in
            guard state.projects.removeValue(forKey: projectId) != nil else { return nil }
            state.projectIdempotency = state.projectIdempotency.filter { $0.value != projectId }
            var active: [String] = []
            var archived: [String] = []
            for (threadId, assigned) in state.projectIds where assigned == projectId {
                state.projectIds.removeValue(forKey: threadId)
                if state.archived.contains(threadId) {
                    archived.append(threadId.description)
                } else {
                    active.append(threadId.description)
                }
            }
            return DeletedProject(
                affectedActiveThreadIds: active,
                affectedArchivedThreadIds: archived)
        }
    }
}

private func storedThreadFromState(
    _ state: InMemoryThreadStoreState,
    _ threadId: ThreadId,
    includeHistory: Bool
) throws -> StoredThread {
    guard let created = state.createdThreads[threadId] else {
        throw ThreadStoreError.threadNotFound(threadId.description)
    }
    let historyItems = state.histories[threadId] ?? []
    let history = includeHistory
        ? StoredThreadHistory(threadId: threadId, items: historyItems)
        : nil
    let name = state.names[threadId].flatMap { $0 }
    let metadata = state.metadataUpdates[threadId]
    let rolloutPath = metadata?.rolloutPath ?? state.rolloutPaths.first { $0.value == threadId }?.key
    let now = Date()
    let section: ThreadSection?
    if let id = state.sections[threadId] {
        section = state.sectionCatalog[id] ?? ThreadSection(
            id: id,
            name: id == PINNED_THREAD_SECTION_ID ? PINNED_THREAD_SECTION_NAME : id)
    } else {
        section = nil
    }
    return StoredThread(
        originator: created.originator.isEmpty ? nil : created.originator,
        threadId: threadId,
        extraConfig: created.extraConfig,
        rolloutPath: rolloutPath,
        forkedFromId: created.forkedFromId,
        parentThreadId: created.parentThreadId,
        preview: metadata?.preview ?? "",
        name: name,
        modelProvider: metadata?.modelProvider ?? "test",
        model: metadata?.model,
        reasoningEffort: metadata?.reasoningEffort.flatMap { $0 },
        createdAt: metadata?.createdAt ?? now,
        updatedAt: metadata?.updatedAt ?? now,
        recencyAt: metadata?.advanceRecencyAt ?? metadata?.updatedAt ?? now,
        archivedAt: state.archived.contains(threadId) ? now : nil,
        section: section,
        sectionPosition: state.sectionPositions[threadId],
        sectionEnteredAt: state.sectionEnteredAt[threadId],
        projectId: state.projectIds[threadId],
        daybreakEnabled: metadata?.daybreakEnabled,
        cwd: metadata?.cwd ?? created.metadata.cwd ?? "",
        cliVersion: metadata?.cliVersion ?? "test",
        source: metadata?.source ?? created.source,
        historyMode: created.historyMode,
        threadSource: metadata?.threadSource.flatMap { $0 } ?? created.threadSource,
        agentNickname: metadata?.agentNickname.flatMap { $0 },
        agentRole: metadata?.agentRole.flatMap { $0 },
        agentPath: metadata?.agentPath.flatMap { $0 },
        gitInfo: metadata.flatMap(gitInfoFromPatch),
        approvalMode: metadata?.approvalMode ?? .never,
        permissionProfile: metadata?.permissionProfile ?? .readOnly(),
        tokenUsage: metadata?.tokenUsage,
        firstUserMessage: metadata?.firstUserMessage,
        history: history)
}

private func historyModeFromState(
    _ state: InMemoryThreadStoreState,
    _ threadId: ThreadId
) -> ThreadHistoryMode {
    state.createdThreads[threadId]?.historyMode ?? .legacy
}

private func gitInfoFromPatch(_ patch: ThreadMetadataPatch) -> GitInfo? {
    guard let gitInfo = patch.gitInfo else { return nil }
    let sha = gitInfo.sha.flatMap { $0 }
    let branch = gitInfo.branch.flatMap { $0 }
    let originUrl = gitInfo.originUrl.flatMap { $0 }
    if sha == nil && branch == nil && originUrl == nil { return nil }
    return GitInfo(
        commitHash: sha.map(GitSha.init),
        branch: branch,
        repositoryUrl: originUrl)
}

private func sessionSourceNickname(_ source: SessionSource) -> String? {
    if case .subAgent(.threadSpawn(_, _, _, let nickname, _)) = source {
        return nickname
    }
    return nil
}

private func sessionSourceAgentRole(_ source: SessionSource) -> String? {
    if case .subAgent(.threadSpawn(_, _, _, _, let role)) = source {
        return role
    }
    return nil
}

private func sessionSourceAgentPath(_ source: SessionSource) -> String? {
    if case .subAgent(.threadSpawn(_, _, let path, _, _)) = source {
        return path?.asStr
    }
    return nil
}
