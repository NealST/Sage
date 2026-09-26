//
//  store.swift
//  CodexThreadStore
//
//  Port of codex-rs/thread-store/src/store.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Async trait + boxed futures map to `async throws` protocol methods.
//  `as_any` is omitted. Methods that need Session or unported backing
//  types keep the Rust default: `ThreadStoreError.unsupported`.
//

import CodexProtocol
import Foundation

/// Why thread persistence is being requested.
public enum PersistContext: String, Codable, Equatable, Sendable {
    case threadPreparation
    case standard
    case subagentSpawn
    case turnStart
    case steeredUserInput

    /// Whether a store may enqueue this checkpoint before returning.
    public func allowsBackgroundPersistence() -> Bool {
        switch self {
        case .threadPreparation, .standard:
            return false
        case .subagentSpawn, .turnStart, .steeredUserInput:
            return true
        }
    }
}

/// Storage-neutral thread persistence boundary.
public protocol ThreadStore: Sendable {
    func defaultHistoryMode() -> ThreadHistoryMode

    func createThread(_ params: CreateThreadParams) async throws
    func stagePendingThreadMetadata(threadId: ThreadId, patch: ThreadMetadataPatch) async throws
    func readPendingThreadMetadata(threadId: ThreadId) async throws -> ThreadMetadataPatch?
    func removePendingThreadMetadata(threadId: ThreadId) async throws
    func resumeThread(_ params: ResumeThreadParams) async throws
    func appendItems(_ params: AppendThreadItemsParams) async throws
    func recordThreadMetadata(_ params: UpdateThreadMetadataParams) async throws
    func persistThread(threadId: ThreadId, context: PersistContext) async throws
    func flushThread(threadId: ThreadId) async throws
    func shutdownThread(threadId: ThreadId) async throws
    func discardThread(threadId: ThreadId) async throws
    func loadHistory(_ params: LoadThreadHistoryParams) async throws -> StoredThreadHistory
    func loadLatestModelContext(_ params: LoadThreadHistoryParams) async throws -> StoredModelContext
    func prepareFork(_ params: PrepareForkParams) async throws -> PreparedFork
    func revertThread(_ params: RevertThreadParams) async throws
    func readThread(_ params: ReadThreadParams) async throws -> StoredThread
    func readThreadByRolloutPath(_ params: ReadThreadByRolloutPathParams) async throws -> StoredThread
    func listThreads(_ params: ListThreadsParams) async throws -> ThreadPage

    func supportsThreadSections() -> Bool
    func listThreadSections(_ params: ListThreadSectionsParams) async throws -> StoredThreadSectionsPage
    func createThreadSection(_ params: CreateThreadSectionParams) async throws -> StoredThreadSection
    func renameThreadSection(_ params: RenameThreadSectionParams) async throws -> StoredThreadSection?
    func deleteThreadSection(_ params: DeleteThreadSectionParams) async throws -> Bool

    func supportsThreadAttachments() -> Bool
    func copyThreadAttachments(sourceThreadId: ThreadId, destinationThreadId: ThreadId) async throws
    func addThreadAttachment(_ params: AddThreadAttachmentParams) async throws -> AddThreadAttachmentOutcome
    func listThreadAttachments(_ params: ListThreadAttachmentsParams) async throws -> ThreadAttachmentPage
    func removeThreadAttachment(_ params: RemoveThreadAttachmentParams) async throws -> RemoveThreadAttachmentOutcome

    func supportsProjects() -> Bool
    func listProjects(_ params: ListProjectsParams) async throws -> StoredProjectsPage
    func readProject(projectId: String) async throws -> StoredProject?
    func createProject(_ params: CreateProjectParams) async throws -> CreatedProject
    func updateProject(_ params: UpdateProjectParams) async throws -> UpdatedProject?
    func moveProject(_ params: MoveProjectParams) async throws -> ProjectMoveOutcome?
    func deleteProject(projectId: String) async throws -> DeletedProject?

    func supportsPaginatedHistoryLists() -> Bool
    func searchThreads(_ params: SearchThreadsParams) async throws -> ThreadSearchPage
    func searchThreadOccurrences(_ params: SearchThreadOccurrencesParams) async throws -> ThreadOccurrenceSearchPage
    func listTurns(_ params: ListTurnsParams) async throws -> TurnPage
    func listItems(_ params: ListItemsParams) async throws -> ItemPage
    func listTimeline(_ params: ListTimelineParams) async throws -> TimelinePage

    func updateThreadMetadata(_ params: UpdateThreadMetadataParams) async throws -> StoredThread?
    func moveThreadToSection(_ params: MoveThreadToSectionParams) async throws
    func archiveThread(_ params: ArchiveThreadParams) async throws
    func archiveThreads(_ params: ArchiveThreadsParams) async throws -> [ThreadId]
    func unarchiveThread(_ params: ArchiveThreadParams) async throws -> StoredThread
    func deleteThread(_ params: DeleteThreadParams) async throws
    func deleteThreads(_ params: DeleteThreadsParams) async throws
}

public extension ThreadStore {
    func defaultHistoryMode() -> ThreadHistoryMode { .legacy }

    func stagePendingThreadMetadata(threadId: ThreadId, patch: ThreadMetadataPatch) async throws {
        _ = threadId
        _ = patch
        throw ThreadStoreError.unsupported(operation: "stage_pending_thread_metadata")
    }

    func readPendingThreadMetadata(threadId: ThreadId) async throws -> ThreadMetadataPatch? {
        _ = threadId
        return nil
    }

    func removePendingThreadMetadata(threadId: ThreadId) async throws {
        _ = threadId
        throw ThreadStoreError.unsupported(operation: "remove_pending_thread_metadata")
    }

    func recordThreadMetadata(_ params: UpdateThreadMetadataParams) async throws {
        _ = try await updateThreadMetadata(params)
    }

    func loadLatestModelContext(_ params: LoadThreadHistoryParams) async throws -> StoredModelContext {
        _ = params
        throw ThreadStoreError.unsupported(operation: "load_latest_model_context")
    }

    func prepareFork(_ params: PrepareForkParams) async throws -> PreparedFork {
        _ = params
        throw ThreadStoreError.unsupported(operation: "prepare_fork")
    }

    func revertThread(_ params: RevertThreadParams) async throws {
        _ = params
        throw ThreadStoreError.unsupported(operation: "revert_thread")
    }

    func supportsThreadSections() -> Bool { false }

    func listThreadSections(_ params: ListThreadSectionsParams) async throws -> StoredThreadSectionsPage {
        _ = params
        throw ThreadStoreError.unsupported(operation: "threadSection/list")
    }

    func createThreadSection(_ params: CreateThreadSectionParams) async throws -> StoredThreadSection {
        _ = params
        throw ThreadStoreError.unsupported(operation: "threadSection/create")
    }

    func renameThreadSection(_ params: RenameThreadSectionParams) async throws -> StoredThreadSection? {
        _ = params
        throw ThreadStoreError.unsupported(operation: "threadSection/update")
    }

    func deleteThreadSection(_ params: DeleteThreadSectionParams) async throws -> Bool {
        _ = params
        throw ThreadStoreError.unsupported(operation: "threadSection/delete")
    }

    func supportsThreadAttachments() -> Bool { false }

    func copyThreadAttachments(sourceThreadId: ThreadId, destinationThreadId: ThreadId) async throws {
        _ = sourceThreadId
        _ = destinationThreadId
        throw ThreadStoreError.unsupported(operation: "copy_thread_attachments")
    }

    func addThreadAttachment(_ params: AddThreadAttachmentParams) async throws -> AddThreadAttachmentOutcome {
        _ = params
        throw ThreadStoreError.unsupported(operation: "thread/attachment/add")
    }

    func listThreadAttachments(_ params: ListThreadAttachmentsParams) async throws -> ThreadAttachmentPage {
        _ = params
        throw ThreadStoreError.unsupported(operation: "thread/attachment/list")
    }

    func removeThreadAttachment(
        _ params: RemoveThreadAttachmentParams
    ) async throws -> RemoveThreadAttachmentOutcome {
        _ = params
        throw ThreadStoreError.unsupported(operation: "thread/attachment/remove")
    }

    func supportsProjects() -> Bool { false }

    func listProjects(_ params: ListProjectsParams) async throws -> StoredProjectsPage {
        _ = params
        throw ThreadStoreError.unsupported(operation: "project/list")
    }

    func readProject(projectId: String) async throws -> StoredProject? {
        _ = projectId
        throw ThreadStoreError.unsupported(operation: "project/read")
    }

    func createProject(_ params: CreateProjectParams) async throws -> CreatedProject {
        _ = params
        throw ThreadStoreError.unsupported(operation: "project/create")
    }

    func updateProject(_ params: UpdateProjectParams) async throws -> UpdatedProject? {
        _ = params
        throw ThreadStoreError.unsupported(operation: "project/update")
    }

    func moveProject(_ params: MoveProjectParams) async throws -> ProjectMoveOutcome? {
        _ = params
        throw ThreadStoreError.unsupported(operation: "project/move")
    }

    func deleteProject(projectId: String) async throws -> DeletedProject? {
        _ = projectId
        throw ThreadStoreError.unsupported(operation: "project/delete")
    }

    func supportsPaginatedHistoryLists() -> Bool { false }

    func searchThreads(_ params: SearchThreadsParams) async throws -> ThreadSearchPage {
        _ = params
        throw ThreadStoreError.unsupported(operation: "thread/search")
    }

    func searchThreadOccurrences(
        _ params: SearchThreadOccurrencesParams
    ) async throws -> ThreadOccurrenceSearchPage {
        _ = params
        throw ThreadStoreError.unsupported(operation: "thread/searchOccurrences")
    }

    func listTurns(_ params: ListTurnsParams) async throws -> TurnPage {
        _ = params
        throw ThreadStoreError.unsupported(operation: "list_turns")
    }

    func listItems(_ params: ListItemsParams) async throws -> ItemPage {
        _ = params
        throw ThreadStoreError.unsupported(operation: "list_items")
    }

    func listTimeline(_ params: ListTimelineParams) async throws -> TimelinePage {
        _ = params
        throw ThreadStoreError.unsupported(operation: "thread/timeline/list")
    }

    func moveThreadToSection(_ params: MoveThreadToSectionParams) async throws {
        _ = params
        throw ThreadStoreError.unsupported(operation: "thread/section/move")
    }

    func archiveThreads(_ params: ArchiveThreadsParams) async throws -> [ThreadId] {
        var archived: [ThreadId] = []
        for threadId in params.threadIds {
            do {
                try await archiveThread(ArchiveThreadParams(threadId: threadId))
                archived.append(threadId)
            } catch {
                if archived.isEmpty { throw error }
            }
        }
        return archived
    }

    func deleteThreads(_ params: DeleteThreadsParams) async throws {
        for threadId in params.threadIds {
            do {
                try await deleteThread(DeleteThreadParams(threadId: threadId))
            } catch let error as ThreadStoreError {
                if case .threadNotFound = error { continue }
                throw error
            }
        }
    }
}
