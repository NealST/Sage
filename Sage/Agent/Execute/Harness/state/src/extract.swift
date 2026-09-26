//
//  extract.swift
//  CodexState
//
//  Port of codex-rs/state/src/extract.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Reuses `isGuardianReviewSource`, `GUARDIAN_THREAD_*`, `enumToString`, and
//  `metadataIsGuardianReview` from lib.swift / thread_metadata.swift.
//  `EventMsg` is still a subset: TokenCount / ThreadGoalUpdated /
//  ThreadSettingsApplied are applied when those cases land in CodexProtocol.
//

import CodexHistory
import CodexProtocol
import Foundation

private let userMessageBegin = "## My request for Codex:"

/// Apply a rollout item to the metadata structure.
public func applyRolloutItem(
    _ metadata: inout ThreadMetadata,
    item: RolloutItem,
    defaultProvider: String
) {
    switch item {
    case .sessionMeta(let metaLine):
        applySessionMetaFromItem(&metadata, metaLine)
    case .turnContext(let turnCtx):
        applyTurnContext(&metadata, turnCtx)
    case .eventMsg(let event):
        applyEventMsg(&metadata, event)
    case .responseItem:
        break
    case .interAgentCommunication, .interAgentCommunicationMetadata:
        break
    case .compacted:
        break
    case .worldState:
        break
    case .retainedContext, .securityRiskScore:
        break
    case .realtimeItem:
        break
    case .tokenUsageRecord:
        break
    }
    if metadata.modelProvider.isEmpty {
        metadata.modelProvider = defaultProvider
    }
}

/// Return whether this rollout item can mutate thread metadata stored in SQLite.
public func rolloutItemAffectsThreadMetadata(_ item: RolloutItem) -> Bool {
    switch item {
    case .sessionMeta, .turnContext:
        return true
    case .eventMsg(let event):
        switch event {
        case .userMessage:
            return true
        case .itemCompleted(let completed):
            if case .userMessage = completed.item {
                return true
            }
            return false
        default:
            // TokenCount / ThreadGoalUpdated / ThreadSettingsApplied are not
            // on EventMsg yet; they will return true when those cases exist.
            return false
        }
    case .responseItem, .interAgentCommunication, .interAgentCommunicationMetadata,
         .compacted, .realtimeItem, .retainedContext, .securityRiskScore,
         .tokenUsageRecord, .worldState:
        return false
    }
}

private func applySessionMetaFromItem(_ metadata: inout ThreadMetadata, _ metaLine: SessionMetaLine) {
    if metadata.id != metaLine.meta.id {
        // Ignore session_meta lines that don't match the canonical thread ID,
        // e.g., forked rollouts that embed the source session metadata.
        return
    }
    metadata.creatorUserId = metadata.creatorUserId ?? metaLine.meta.creatorUserId
    metadata.creatorAccountId = metadata.creatorAccountId ?? metaLine.meta.creatorAccountId
    metadata.id = metaLine.meta.id
    metadata.source = enumToString(metaLine.meta.source)
    if metadata.originator == nil && !metaLine.meta.originator.isEmpty {
        metadata.originator = metaLine.meta.originator
    }
    // Later SessionMeta lines do not redefine the canonical history_mode.
    metadata.threadSource = metaLine.meta.threadSource
    metadata.agentNickname = metaLine.meta.agentNickname
    metadata.agentRole = metaLine.meta.agentRole
    metadata.agentPath = metaLine.meta.agentPath
    if let provider = metaLine.meta.modelProvider {
        metadata.modelProvider = provider
    }
    if !metaLine.meta.cliVersion.isEmpty {
        metadata.cliVersion = metaLine.meta.cliVersion
    }
    if !metaLine.meta.cwd.isEmpty {
        metadata.cwd = metaLine.meta.cwd
    }
    if let git = metaLine.git {
        metadata.gitSha = git.commitHash?.value
        metadata.gitBranch = git.branch
        metadata.gitOriginUrl = git.repositoryUrl
    }
}

private func applyTurnContext(_ metadata: inout ThreadMetadata, _ turnCtx: TurnContextItem) {
    if metadata.cwd.isEmpty {
        metadata.cwd = turnCtx.cwd
    }
    metadata.model = turnCtx.model
    metadata.reasoningEffort = turnCtx.effort
    metadata.sandboxPolicy = enumToString(turnCtx.resolvedPermissionProfile())
    metadata.approvalMode = enumToString(turnCtx.approvalPolicy)
}

private func applyEventMsg(_ metadata: inout ThreadMetadata, _ event: EventMsg) {
    switch event {
    case .userMessage(let user) where !metadataIsGuardianReview(metadata):
        applyUserMessage(&metadata, user)
    case .itemCompleted(let completed):
        if case .userMessage(let user) = completed.item, !metadataIsGuardianReview(metadata) {
            applyUserMessage(&metadata, user.asLegacyUserMessageEvent())
        }
    default:
        // TokenCount / ThreadGoalUpdated / ThreadSettingsApplied wait on EventMsg.
        break
    }
}

private func applyUserMessage(_ metadata: inout ThreadMetadata, _ user: UserMessageEvent) {
    let preview = userMessagePreview(user)
    if metadata.firstUserMessage == nil {
        metadata.firstUserMessage = preview
    }
    setPreviewIfEmpty(&metadata, preview)
    if metadata.title.isEmpty {
        let title = stripUserMessagePrefix(user.message)
        if !title.isEmpty {
            metadata.title = title
        }
    }
}

private func setPreviewIfEmpty(_ metadata: inout ThreadMetadata, _ preview: String?) {
    if metadata.preview == nil {
        metadata.preview = preview
    }
}

private func userMessagePreview(_ user: UserMessageEvent) -> String? {
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

private func stripUserMessagePrefix(_ text: String) -> String {
    if let range = text.range(of: userMessageBegin) {
        return String(text[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return text.trimmingCharacters(in: .whitespacesAndNewlines)
}
