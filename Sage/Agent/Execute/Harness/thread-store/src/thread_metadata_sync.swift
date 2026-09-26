//
//  thread_metadata_sync.swift
//  CodexThreadStore
//
//  Port of codex-rs/thread-store/src/thread_metadata_sync.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  In-memory merge of append-derived metadata patches. Git collection
//  (codex-git-utils) and remote HTTP are skipped. TokenCount /
//  ThreadGoalUpdated / ThreadSettingsApplied are not in the EventMsg
//  subset yet.
//

import CodexHistory
import CodexProtocol
import CodexState
import Foundation

private let threadUpdatedAtTouchInterval: TimeInterval = 5
private let threadStoreCliVersion = "0.0.0-sage"
private let userMessageBegin = "## My request for Codex:"

/// Live-thread helper that derives metadata updates from appended rollout items.
struct ThreadMetadataSync: Sendable {
    var threadId: ThreadId
    var cwdSeen: Bool
    var previewSeen: Bool
    var firstUserMessageSeen: Bool
    var titleSeen: Bool
    var pendingUpdate: ThreadMetadataPatch?
    var pendingUpdateGeneration: UInt64
    var lastTouchPersistedAt: Date?
    var deferCreateUpdateUntilHistoryExists: Bool
    var deferResumeUpdateUntilAppend: Bool
}

struct PendingThreadMetadataPatch: Sendable {
    var patch: ThreadMetadataPatch
    var generation: UInt64
}

extension ThreadMetadataSync {
    static func forCreate(_ params: CreateThreadParams) async -> ThreadMetadataSync {
        let createdAt = Date()
        let cwd = params.metadata.cwd ?? ""
        let guardianReview = isGuardianReviewSource(params.source)
        let update = ThreadMetadataPatch(
            name: (guardianReview && params.historyMode == .paginated)
                ? .some(GUARDIAN_THREAD_TITLE) : nil,
            preview: guardianReview ? GUARDIAN_THREAD_PREVIEW : nil,
            title: guardianReview ? GUARDIAN_THREAD_TITLE : nil,
            modelProvider: params.metadata.modelProvider,
            createdAt: createdAt,
            updatedAt: createdAt,
            source: params.source,
            creatorUserId: params.creatorUserId,
            creatorAccountId: params.creatorAccountId,
            originator: params.originator.isEmpty ? nil : params.originator,
            threadSource: .some(params.threadSource),
            agentNickname: .some(sessionSourceNickname(params.source)),
            agentRole: .some(sessionSourceAgentRole(params.source)),
            agentPath: .some(sessionSourceAgentPath(params.source)),
            cwd: cwd,
            cliVersion: threadStoreCliVersion,
            memoryMode: params.metadata.memoryMode
        )
        return ThreadMetadataSync(
            threadId: params.threadId,
            cwdSeen: !cwd.isEmpty,
            previewSeen: guardianReview,
            firstUserMessageSeen: guardianReview,
            titleSeen: guardianReview,
            pendingUpdate: update,
            pendingUpdateGeneration: 1,
            lastTouchPersistedAt: nil,
            deferCreateUpdateUntilHistoryExists: true,
            deferResumeUpdateUntilAppend: false
        )
    }

    static func forResume(
        _ params: ResumeThreadParams,
        metadata: ThreadMetadata? = nil
    ) -> ThreadMetadataSync {
        let guardianReview = metadata.flatMap { sessionSourceFromMetadataString($0.source) }
            .map(isGuardianReviewSource) ?? false
        var sync = ThreadMetadataSync(
            threadId: params.threadId,
            cwdSeen: (params.metadata.cwd?.isEmpty == false),
            previewSeen: guardianReview
                || (metadata?.preview?.isEmpty == false),
            firstUserMessageSeen: guardianReview
                || metadata?.firstUserMessage != nil,
            titleSeen: guardianReview
                || (metadata.map { !$0.title.isEmpty } ?? false),
            pendingUpdate: nil,
            pendingUpdateGeneration: 0,
            lastTouchPersistedAt: nil,
            deferCreateUpdateUntilHistoryExists: false,
            deferResumeUpdateUntilAppend: false
        )
        if let history = params.history {
            sync.recordResumeHistory(history)
        }
        return sync
    }

    mutating func recordResumeHistory(_ history: [RolloutItem]) {
        let update = observeResumeHistory(history)
        mergePendingUpdate(update)
        deferResumeUpdateUntilAppend = pendingUpdate != nil
    }

    func takePendingUpdate() -> PendingThreadMetadataPatch? {
        pendingUpdate.map { PendingThreadMetadataPatch(patch: $0, generation: pendingUpdateGeneration) }
    }

    func takePendingUpdateForExistingHistory() -> PendingThreadMetadataPatch? {
        if deferCreateUpdateUntilHistoryExists { return nil }
        if deferResumeUpdateUntilAppend { return nil }
        return takePendingUpdate()
    }

    mutating func markPendingUpdateApplied(_ update: PendingThreadMetadataPatch) {
        if pendingUpdateGeneration == update.generation {
            pendingUpdate = nil
        }
        if update.patch.updatedAt != nil {
            lastTouchPersistedAt = Date()
        }
    }

    mutating func observeAppendedItems(_ items: [RolloutItem]) -> PendingThreadMetadataPatch? {
        deferCreateUpdateUntilHistoryExists = false
        deferResumeUpdateUntilAppend = false
        let affectsMetadata = items.contains(where: rolloutItemAffectsThreadMetadata)
        let advancesRecency = items.contains { item in
            if case .eventMsg(.turnStarted) = item { return true }
            return false
        }
        var update = affectsMetadata
            ? (observeItems(items) ?? threadUpdatedAtTouch())
            : threadUpdatedAtTouch()
        if advancesRecency {
            update.advanceRecencyAt = Date()
        }
        mergePendingUpdate(update)
        if !affectsMetadata,
           !(pendingUpdate.map(updateHasMetadataFacts) ?? false),
           let lastTouch = lastTouchPersistedAt,
           Date().timeIntervalSince(lastTouch) < threadUpdatedAtTouchInterval
        {
            return nil
        }
        return takePendingUpdate()
    }

    private mutating func observeItems(_ items: [RolloutItem]) -> ThreadMetadataPatch? {
        observeItems(
            items,
            update: ThreadMetadataPatch(updatedAt: Date())
        )
    }

    private mutating func observeResumeHistory(_ items: [RolloutItem]) -> ThreadMetadataPatch? {
        guard var update = observeItems(items, update: ThreadMetadataPatch()) else {
            return nil
        }
        if canonicalHistoryModeFromRolloutItems(items) == .paginated {
            update.gitInfo = nil
            update.memoryMode = nil
        }
        return update
    }

    private mutating func observeItems(
        _ items: [RolloutItem],
        update: ThreadMetadataPatch
    ) -> ThreadMetadataPatch? {
        if items.isEmpty { return nil }
        var update = update
        for item in items {
            switch item {
            case .sessionMeta(let metaLine) where metaLine.meta.id == threadId:
                if isGuardianReviewSource(metaLine.meta.source) {
                    previewSeen = true
                    firstUserMessageSeen = true
                    titleSeen = true
                    update.preview = GUARDIAN_THREAD_PREVIEW
                }
                update.createdAt = parseSessionTimestamp(metaLine.meta.timestamp)
                update.creatorUserId = metaLine.meta.creatorUserId
                update.creatorAccountId = metaLine.meta.creatorAccountId
                update.source = metaLine.meta.source
                if !metaLine.meta.originator.isEmpty {
                    update.originator = metaLine.meta.originator
                }
                update.threadSource = .some(metaLine.meta.threadSource)
                update.agentNickname = .some(metaLine.meta.agentNickname)
                update.agentRole = .some(metaLine.meta.agentRole)
                update.agentPath = .some(metaLine.meta.agentPath)
                if let modelProvider = metaLine.meta.modelProvider, !modelProvider.isEmpty {
                    update.modelProvider = modelProvider
                }
                if !metaLine.meta.cliVersion.isEmpty {
                    update.cliVersion = metaLine.meta.cliVersion
                }
                if !metaLine.meta.cwd.isEmpty {
                    cwdSeen = true
                    update.cwd = metaLine.meta.cwd
                }
                if let gitInfo = metaLine.git {
                    update.gitInfo = gitInfoPatchFromObservation(gitInfo)
                }
                if let memoryMode = metaLine.meta.memoryMode.flatMap(parseMemoryMode) {
                    update.memoryMode = memoryMode
                }
            case .turnContext(let turnCtx):
                if !cwdSeen {
                    cwdSeen = true
                    update.cwd = turnCtx.cwd
                }
                update.model = turnCtx.model
                update.reasoningEffort = .some(turnCtx.effort)
                update.approvalMode = turnCtx.approvalPolicy
                update.permissionProfile = turnCtx.resolvedPermissionProfile()
            case .eventMsg(.userMessage(let user)):
                observeUserMessage(user, update: &update)
            case .eventMsg(.itemCompleted(let event)):
                if case .userMessage(let user) = event.item,
                   !firstUserMessageSeen || !previewSeen || !titleSeen
                {
                    observeUserMessage(user.asLegacyUserMessageEvent(), update: &update)
                }
            default:
                break
            }
        }
        return update
    }

    private mutating func observeUserMessage(
        _ user: UserMessageEvent,
        update: inout ThreadMetadataPatch
    ) {
        if (!firstUserMessageSeen || !previewSeen), let preview = userMessagePreview(user) {
            if !firstUserMessageSeen {
                firstUserMessageSeen = true
                update.firstUserMessage = preview
            }
            if !previewSeen {
                previewSeen = true
                update.preview = preview
            }
        }
        if !titleSeen {
            let title = stripUserMessagePrefix(user.message)
            if !title.isEmpty {
                titleSeen = true
                update.title = title
            }
        }
    }

    private mutating func mergePendingUpdate(_ update: ThreadMetadataPatch?) {
        guard let update else { return }
        if pendingUpdate != nil {
            pendingUpdate?.merge(update)
        } else {
            pendingUpdate = update
        }
        pendingUpdateGeneration = pendingUpdateGeneration &+ 1
    }
}

func rolloutItemAffectsThreadMetadata(_ item: RolloutItem) -> Bool {
    switch item {
    case .sessionMeta, .turnContext:
        return true
    case .eventMsg(.userMessage):
        return true
    case .eventMsg(.itemCompleted(let event)):
        if case .userMessage = event.item { return true }
        return false
    default:
        return false
    }
}

private func parseMemoryMode(_ value: String) -> ThreadMemoryMode? {
    switch value {
    case "enabled": return .enabled
    case "disabled": return .disabled
    default: return nil
    }
}

func parseSessionTimestamp(_ value: String) -> Date? {
    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = iso.date(from: value) { return date }
    iso.formatOptions = [.withInternetDateTime]
    if let date = iso.date(from: value) { return date }
    let compact = DateFormatter()
    compact.locale = Locale(identifier: "en_US_POSIX")
    compact.timeZone = TimeZone(secondsFromGMT: 0)
    compact.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
    return compact.date(from: value)
}

private func threadUpdatedAtTouch() -> ThreadMetadataPatch {
    ThreadMetadataPatch(updatedAt: Date())
}

func updateHasMetadataFacts(_ update: ThreadMetadataPatch) -> Bool {
    update.rolloutPath != nil
        || update.preview != nil
        || update.title != nil
        || update.modelProvider != nil
        || update.model != nil
        || update.reasoningEffort != nil
        || update.createdAt != nil
        || update.advanceRecencyAt != nil
        || update.source != nil
        || update.originator != nil
        || update.creatorUserId != nil
        || update.creatorAccountId != nil
        || update.threadSource != nil
        || update.agentNickname != nil
        || update.agentRole != nil
        || update.agentPath != nil
        || update.cwd != nil
        || update.cliVersion != nil
        || update.approvalMode != nil
        || update.permissionProfile != nil
        || update.tokenUsage != nil
        || update.firstUserMessage != nil
        || update.gitInfo != nil
        || update.memoryMode != nil
}

func gitInfoPatchFromObservation(_ gitInfo: GitInfo) -> GitInfoPatch {
    GitInfoPatch(
        sha: gitInfo.commitHash.map { .some($0.value) },
        branch: gitInfo.branch.map { .some($0) },
        originUrl: gitInfo.repositoryUrl.map { .some($0) }
    )
}

func sessionSourceFromMetadataString(_ raw: String) -> SessionSource? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if let data = trimmed.data(using: .utf8),
       let source = try? JSONDecoder().decode(SessionSource.self, from: data)
    {
        return source
    }
    switch trimmed {
    case "cli": return .cli
    case "vscode": return .vsCode
    case "exec": return .exec
    case "mcp": return .mcp
    case "unknown": return .unknown
    default: return nil
    }
}

fileprivate func sessionSourceNickname(_ source: SessionSource) -> String? {
    if case .subAgent(.threadSpawn(_, _, _, let nickname, _)) = source {
        return nickname
    }
    return nil
}

fileprivate func sessionSourceAgentRole(_ source: SessionSource) -> String? {
    if case .subAgent(.threadSpawn(_, _, _, _, let role)) = source {
        return role
    }
    return nil
}

fileprivate func sessionSourceAgentPath(_ source: SessionSource) -> String? {
    if case .subAgent(.threadSpawn(_, _, let path, _, _)) = source {
        return path?.asStr
    }
    return nil
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
