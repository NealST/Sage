//
//  rollout_reconstruction.swift
//  Sage
//
//  Port of codex-rs/core/src/session/rollout_reconstruction.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Verified answers and response items are restored from the rollout.
//  A compaction with replacement history, a window number, and resume
//  metadata (or paginated history) bounds that replay: its replacement
//  history and verified-answer snapshot are installed, then only newer
//  retained-context and response items are recorded. Function and custom
//  tool outputs in that suffix are truncated with the model policy.
//  A metadata token limit replaces that policy and already includes the
//  serialization allowance. `ThreadRolledBack` drops that many newest
//  user turns from the history restored so far. A suffix compaction
//  without replacement history rebuilds that history from the user
//  messages recorded so far and the persisted summary. Choosing that
//  checkpoint skips user turns `ThreadRolledBack` already dropped, so a
//  replacement history inside one of those turns is not the base. A newer
//  compaction that itself cannot bound replay still blocks older ones.
//  World state from the surviving turns is replayed afterward: a compaction
//  clears the baseline, a full snapshot replaces it, and a patch merges in.
//  The newest surviving turn's reference context is restored, unless a
//  compaction cleared it or a legacy compaction rebuilt the suffix.
//  That same turn restores previous turn settings. An unfinished suffix
//  after resume metadata leaves those settings to the metadata.
//

import CodexCore
import CodexHistory
import CodexProtocol
import CodexUtils
import Foundation

enum RolloutReconstruction {
    static func items(from history: ContextManager) -> [ResponseItem] {
        history.items.map(\.item)
    }

    /// rust `reconstruct_history_from_rollout` for verified answers and
    /// response items. The default policy is the catalog byte limit.
    static func restoreVerifiedAnswers(
        from items: [RolloutItem],
        into history: ContextManager,
        historyMode: ThreadHistoryMode = .legacy,
        truncationPolicy: TruncationPolicy = .bytes(10_000)
    ) {
        let scan = scanReplay(items, historyMode: historyMode)
        let suffix: ArraySlice<RolloutItem>
        if let index = scan.checkpoint,
           case .compacted(let compacted) = items[index] {
            if let replacement = compacted.replacementHistory {
                history.replaceAnnotated(replacement.map {
                    CodexCore.ResponseItemEnvelope($0.item)
                })
                if history.userMessageRevision < .max {
                    history.userMessageRevision += 1
                }
            }
            let snapshot = compacted.retainedContext.flatMap(restoredVerifiedAnswers(from:))
            history.installRestoredVerifiedAnswers(
                snapshot?.answers ?? [],
                incomplete: snapshot?.incomplete ?? false
            )
            suffix = items[(index + 1)...]
        } else {
            suffix = items[...]
        }
        let sawLegacyCompaction = recordRestoredSuffix(
            suffix, into: history, truncationPolicy: truncationPolicy)
        history.worldStateBaseline = replayedWorldStateBaseline(scan.worldState)
        history.setReferenceContextItem(sawLegacyCompaction ? nil : scan.referenceContext)
        history.setReconstructedTurnSettings(scan.previousTurnSettings)
    }

    private static func recordRestoredSuffix(
        _ items: ArraySlice<RolloutItem>,
        into history: ContextManager,
        truncationPolicy: TruncationPolicy
    ) -> Bool {
        var sawLegacyCompaction = false
        for item in items {
            switch item {
            case .retainedContext:
                guard let answer = verifiedAnswer(from: item) else { continue }
                history.recordVerifiedAnswer(answer)
            case .responseItem(let envelope):
                guard keepsReconstructedResponseItem(envelope) else { continue }
                history.recordItems([
                    truncatedRestoredResponseItem(envelope, policy: truncationPolicy)
                ])
            case .eventMsg(.threadRolledBack(let rollback)):
                history.dropLastUserTurns(rollback.numTurns)
            case .compacted(let compacted):
                guard compacted.replacementHistory == nil else { continue }
                sawLegacyCompaction = true
                Self.rebuildLegacyCompactedHistory(compacted, into: history)
            default:
                continue
            }
        }
        return sawLegacyCompaction
    }

    /// rust suffix `Compacted` without `replacement_history`. User-message ids
    /// stay when the snapshot is thread-owned and are cleared otherwise.
    private static func rebuildLegacyCompactedHistory(
        _ compacted: CompactedItem,
        into history: ContextManager
    ) {
        var userMessages = collectAnnotatedUserMessages(history.items)
        if history.guardianReviewMode != .threadOwned {
            for index in userMessages.indices {
                userMessages[index].id = nil
            }
        }
        history.replaceAnnotated(
            buildCompactedHistory(userMessages: userMessages, summaryText: compacted.message)
        )
        if history.userMessageRevision < .max {
            history.userMessageRevision += 1
        }
    }

    /// rust reverse replay for the history checkpoint. `ThreadRolledBack`
    /// skips that many newer user-turn segments. A surviving compaction
    /// bounds replay only when it has replacement history, a window number,
    /// and resume metadata (or the history is paginated). A newer surviving
    /// compaction that cannot bound replay blocks every older one.
    private static func scanReplay(
        _ items: [RolloutItem],
        historyMode: ThreadHistoryMode
    ) -> (
        checkpoint: Int?,
        worldState: [RolloutItem],
        referenceContext: TurnContextItem?,
        previousTurnSettings: ReconstructedTurnSettings?
    ) {
        var pendingRollbackTurns = 0
        var segment = CompactionReplaySegment()
        var segmentOpen = false
        var surviving: [(index: Int, canBound: Bool)] = []
        var worldStateNewestFirst: [RolloutItem] = []
        var referenceContext = ReplayReferenceContext.neverSet
        var previousTurnSettings: ReconstructedTurnSettings?
        let resumeMetadata = inputCheckpointResumeMetadata(items, historyMode: historyMode)

        func closeSegment(dropIncompleteSettings: Bool) {
            defer {
                segment = CompactionReplaySegment()
                segmentOpen = false
            }
            guard segmentOpen else { return }
            if pendingRollbackTurns > 0 {
                if segment.countsAsUserTurn {
                    pendingRollbackTurns -= 1
                }
                return
            }
            if let index = segment.newestCompaction {
                surviving.append((index, segment.newestCompactionCanBound))
            }
            worldStateNewestFirst.append(contentsOf: segment.worldStateReplay)
            if case .neverSet = referenceContext,
               segmentHasContextBaseline(segment) || segment.referenceContext == .cleared {
                referenceContext = segment.referenceContext
            }
            if dropIncompleteSettings && !segment.turnCompleted {
                segment.previousTurnSettings = nil
            }
            if previousTurnSettings == nil && segmentHasContextBaseline(segment) {
                previousTurnSettings = segment.previousTurnSettings
            }
        }

        for index in items.indices.reversed() {
            switch items[index] {
            case .eventMsg(.threadRolledBack(let rollback)):
                pendingRollbackTurns = saturatingAdd(
                    pendingRollbackTurns, Int(exactly: rollback.numTurns) ?? Int.max)
            case .eventMsg(.userMessage):
                segmentOpen = true
                segment.countsAsUserTurn = true
            case .eventMsg(.turnComplete(let event)):
                segmentOpen = true
                segment.turnCompleted = true
                if segment.turnId == nil {
                    segment.turnId = event.turnId
                }
            case .eventMsg(.turnAborted(let event)):
                segmentOpen = true
                if segment.turnId == nil {
                    segment.turnId = event.turnId
                }
            case .eventMsg(.turnStarted(let event)):
                if segmentOpen && turnIdsCompatible(segment.turnId, event.turnId) {
                    closeSegment(dropIncompleteSettings: false)
                }
            case .responseItem(let envelope):
                guard isUserTurnBoundary(envelope.item) else { continue }
                segmentOpen = true
                segment.countsAsUserTurn = true
            case .compacted(let compacted):
                segmentOpen = true
                segment.worldStateReplay.append(items[index])
                if segment.referenceContext == .neverSet {
                    segment.referenceContext = .cleared
                }
                guard segment.newestCompaction == nil else { continue }
                segment.newestCompaction = index
                segment.newestCompactionCanBound = compactionBoundsReplay(
                    compacted, historyMode: historyMode)
            case .worldState:
                segmentOpen = true
                segment.worldStateReplay.append(items[index])
            case .turnContext(let context):
                segmentOpen = true
                if segment.turnId == nil {
                    segment.turnId = context.turnId
                }
                if turnIdsCompatible(segment.turnId, context.turnId) {
                    segment.previousTurnSettings = ReconstructedTurnSettings(
                        model: context.model,
                        compHash: context.compHash,
                        realtimeActive: context.realtimeActive
                    )
                    if segment.referenceContext == .neverSet {
                        segment.referenceContext = .latest(context)
                    }
                }
            default:
                continue
            }
        }
        closeSegment(dropIncompleteSettings: resumeMetadata != nil)

        var checkpoint: Int?
        for candidate in surviving {
            if candidate.canBound {
                checkpoint = candidate.index
            }
            break
        }
        let reference: TurnContextItem?
        if case .latest(let context) = referenceContext {
            reference = context
        } else {
            reference = nil
        }
        if previousTurnSettings == nil {
            previousTurnSettings = reconstructedTurnSettings(from: resumeMetadata)
        }
        return (checkpoint, Array(worldStateNewestFirst.reversed()), reference, previousTurnSettings)
    }
}

private struct CompactionReplaySegment {
    var turnId: String?
    var countsAsUserTurn = false
    var newestCompaction: Int?
    var newestCompactionCanBound = false
    /// Newest first. Compactions clear the baseline when replayed forward.
    var worldStateReplay: [RolloutItem] = []
    var referenceContext: ReplayReferenceContext = .neverSet
    var previousTurnSettings: ReconstructedTurnSettings?
    var turnCompleted = false
}

private enum ReplayReferenceContext: Equatable {
    case neverSet
    case cleared
    case latest(TurnContextItem)
}

/// A user turn, or a full world-state snapshot newer than this segment's
/// latest compaction, is enough to keep that segment's reference context.
private func segmentHasContextBaseline(_ segment: CompactionReplaySegment) -> Bool {
    if segment.countsAsUserTurn { return true }
    for item in segment.worldStateReplay {
        if case .compacted = item { return false }
        if case .worldState(let state) = item, state.full { return true }
    }
    return false
}

/// rust chronological world-state replay. A patch with no full snapshot is ignored.
private func replayedWorldStateBaseline(_ items: [RolloutItem]) -> WorldStateSnapshot? {
    var baseline: WorldStateSnapshot?
    for item in items {
        switch item {
        case .compacted:
            baseline = nil
        case .worldState(let state) where state.full:
            baseline = WorldStateSnapshot(jsonSections: state.state)
        case .worldState(let state):
            guard var current = baseline else { continue }
            current.applyMergePatch(state.state)
            baseline = current
        default:
            continue
        }
    }
    return baseline
}

private func compactionBoundsReplay(
    _ compacted: CompactedItem,
    historyMode: ThreadHistoryMode
) -> Bool {
    compacted.replacementHistory != nil
        && compacted.windowNumber != nil
        && (compacted.resumeMetadata != nil || historyMode == .paginated)
}

/// Resume metadata of the newest compaction, when that compaction can bound replay.
private func inputCheckpointResumeMetadata(
    _ items: [RolloutItem],
    historyMode: ThreadHistoryMode
) -> CodexProtocol.JSONValue? {
    for item in items.reversed() {
        guard case .compacted(let compacted) = item else { continue }
        guard compactionBoundsReplay(compacted, historyMode: historyMode) else { return nil }
        return compacted.resumeMetadata
    }
    return nil
}

private func reconstructedTurnSettings(from metadata: CodexProtocol.JSONValue?) -> ReconstructedTurnSettings? {
    guard let settings = metadata?.objectValue?["previous_turn_settings"]?.objectValue,
          let model = settings["model"]?.stringValue
    else { return nil }
    return ReconstructedTurnSettings(
        model: model,
        compHash: settings["comp_hash"]?.stringValue,
        realtimeActive: settings["realtime_active"]?.boolValue
    )
}

private func turnIdsCompatible(_ active: String?, _ started: String?) -> Bool {
    guard let active, let started else { return true }
    return active == started
}

private func saturatingAdd(_ lhs: Int, _ rhs: Int) -> Int {
    let (sum, overflow) = lhs.addingReportingOverflow(rhs)
    return overflow ? Int.max : sum
}

private func restoredVerifiedAnswers(
    from checkpoint: CodexProtocol.JSONValue
) -> (answers: [RetainedVerifiedAnswer], incomplete: Bool)? {
    guard let object = checkpoint.objectValue else { return nil }
    var answers: [RetainedVerifiedAnswer] = []
    for value in object["verified_answers"]?.arrayValue ?? [] {
        guard let fields = value.objectValue,
              let turnId = fields["turn_id"]?.stringValue,
              let callId = fields["call_id"]?.stringValue
        else { continue }
        var questions: [RetainedVerifiedQuestion] = []
        for question in fields["questions"]?.arrayValue ?? [] {
            guard let questionFields = question.objectValue,
                  let text = questionFields["question"]?.stringValue,
                  let answer = questionFields["answer"]?.stringValue
            else { continue }
            questions.append(RetainedVerifiedQuestion(question: text, answer: answer))
        }
        let order = UInt64(exactly: fields["order"]?.intValue ?? 0) ?? 0
        answers.append(
            RetainedVerifiedAnswer(
                turnId: turnId,
                callId: callId,
                questions: questions,
                acceptanceOrder: order
            )
        )
    }
    return (answers, object["incomplete"]?.boolValue == true)
}

/// rust `is_api_message`. System text, unauthored configuration updates,
/// compaction triggers, and unknown items stay out of the restored history.
func keepsReconstructedResponseItem(_ envelope: CodexHistory.ResponseItemEnvelope) -> Bool {
    switch envelope.item {
    case .message(_, let role, _, _, _):
        return role != "system"
    case .configurationUpdate:
        return envelope.metadata?.harnessAuthoredConfiguration == true
    case .compactionTrigger, .other:
        return false
    default:
        return true
    }
}

/// rust `record_items_with_metadata` for function and custom tool outputs.
func truncatedRestoredResponseItem(
    _ envelope: CodexHistory.ResponseItemEnvelope,
    policy: TruncationPolicy
) -> ResponseItem {
    let applied: TruncationPolicy
    if let limit = envelope.metadata?.historyTruncationTokenLimit {
        applied = .tokens(Int(exactly: limit) ?? Int.max)
    } else {
        applied = withSerializationAllowance(policy)
    }
    switch envelope.item {
    case .functionCallOutput(let id, let callId, let name, let namespace, var output, let passthrough):
        truncateFunctionOutputPayload(
            &output, policy: applied, estimateAudioTokenCount: estimateAudioTokenCount)
        return .functionCallOutput(
            id: id, callId: callId, name: name, namespace: namespace,
            output: output, internalChatMessageMetadataPassthrough: passthrough)
    case .customToolCallOutput(let id, let callId, let name, var output, let passthrough):
        truncateFunctionOutputPayload(
            &output, policy: applied, estimateAudioTokenCount: estimateAudioTokenCount)
        return .customToolCallOutput(
            id: id, callId: callId, name: name,
            output: output, internalChatMessageMetadataPassthrough: passthrough)
    default:
        return envelope.item
    }
}
