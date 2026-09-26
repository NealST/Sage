//
//  state_session.swift
//  Sage
//
//  Port of codex-rs/core/src/state/session.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  SessionConfiguration lives with Session. History uses ContextManager from
//  CodexCore. Startup prewarm handles are optional boxes until Phase 6.
//

import CodexCore
import CodexProtocol
import CodexSandboxing
import Foundation

enum ReasoningEffortPin: Equatable, Sendable {
    case unset
    case compacted
    case active(model: String, effort: ReasoningEffort)

    func get(_ model: String) -> ReasoningEffort? {
        if case .active(let pinnedModel, let effort) = self, pinnedModel == model {
            return effort
        }
        return nil
    }

    mutating func pin(model: String, effort: ReasoningEffort) -> ReasoningEffort {
        if let pinned = get(model) { return pinned }
        self = .active(model: model, effort: effort)
        return effort
    }
}

struct PreviousTurnSettings: Equatable, Sendable {
    var model: String
    var realtimeActive: Bool

    init(model: String, realtimeActive: Bool = false) {
        self.model = model
        self.realtimeActive = realtimeActive
    }
}

enum SessionStartSource: Equatable, Sendable {
    case user
    case resume
    case fork
}

final class SessionState: @unchecked Sendable {
    var sessionConfiguration: SessionConfiguration
    var activeDisabledPluginIds: [String] = []
    var baseInstructionsProvenance: BaseInstructionsProvenance?
    var history: ContextManager
    var historyReset = false
    var latestRateLimits: RateLimitSnapshot?
    var latestTokenUsageRecord: TokenUsageRecord?
    var serverReasoningIncluded = false
    var mcpDependencyPrompted: Set<String> = []
    var additionalContext = AdditionalContextStore()
    var lastStartedTurnId: String?
    var reasoningEffortPin: ReasoningEffortPin = .unset
    var shuttingDown = false
    var currentTimeReminder = CurrentTimeReminderState()
    var activeConnectorSelection: Set<String> = []
    var pendingSessionStartSources: [SessionStartSource] = []
    var nextTurnIsFirst = true

    var previousTurnSettings: PreviousTurnSettings?
    var autoCompactWindow: AutoCompactWindow
    var grantedPermissionsByEnvironmentId: [String: AdditionalPermissionProfile] = [:]

    init(
        sessionConfiguration: SessionConfiguration,
        autoCompactWindowIds: AutoCompactWindowIds = .newInitial(),
        history: ContextManager = ContextManager()
    ) {
        self.sessionConfiguration = sessionConfiguration
        self.history = history
        self.autoCompactWindow = .newWithIds(autoCompactWindowIds)
    }

    func previousTurnSettingsValue() -> PreviousTurnSettings? {
        previousTurnSettings
    }

    func setPreviousTurnSettings(_ value: PreviousTurnSettings?) {
        previousTurnSettings = value
    }

    func setNextTurnIsFirst(_ value: Bool) {
        nextTurnIsFirst = value
    }

    func takeNextTurnIsFirst() -> Bool {
        let isFirst = nextTurnIsFirst
        nextTurnIsFirst = false
        return isFirst
    }

    func recordItems(_ items: [ResponseItem]) {
        history.recordItems(items)
    }

    func replaceAnnotatedHistory(
        _ items: [ResponseItemEnvelope],
        referenceContextItem: TurnContextItem?,
        replacement: HistoryReplacement
    ) {
        let invalidateReviews: Bool
        switch replacement {
        case .compaction(let hash):
            invalidateReviews = history.replaceCompacted(items, reviewerCompactionHash: hash)
        case .reset:
            history.replaceAnnotated(items)
            invalidateReviews = true
        }
        if invalidateReviews {
            historyReset = true
        }
        history.setReferenceContextItem(referenceContextItem)
        autoCompactWindow.clearPrefill()
    }

    func setTokenInfo(_ info: TokenUsageInfo?) {
        history.setTokenInfo(info)
    }

    func recordTokenUsage(
        threadId: ThreadId,
        turnId: String,
        sessionId: SessionId,
        rootTurnId: String,
        responseId: String,
        usage: CodexProtocol.TokenUsage
    ) -> TokenUsageRecord {
        var turnTokenUsage = CodexProtocol.TokenUsage()
        if let latest = latestTokenUsageRecord, latest.turnId == turnId {
            turnTokenUsage = latest.turnTokenUsage
        }
        turnTokenUsage.addAssign(usage)
        var threadTokenUsage = latestTokenUsageRecord?.threadTokenUsage ?? CodexProtocol.TokenUsage()
        threadTokenUsage.addAssign(usage)
        let record = TokenUsageRecord(
            threadId: threadId,
            turnId: turnId,
            sessionId: sessionId,
            rootTurnId: rootTurnId,
            responseId: responseId,
            usage: usage,
            turnTokenUsage: turnTokenUsage,
            threadTokenUsage: threadTokenUsage
        )
        latestTokenUsageRecord = record
        return record
    }

    func updateTokenInfoFromUsage(_ usage: CodexProtocol.TokenUsage, modelContextWindow: Int64?) {
        history.updateTokenInfo(usage, modelContextWindow: modelContextWindow)
    }

    func ensureAutoCompactWindowServerPrefillFromUsage(_ usage: CodexProtocol.TokenUsage) {
        autoCompactWindow.ensureServerObservedPrefillFromUsage(usage)
    }

    func setAutoCompactWindowEstimatedPrefill(_ tokens: Int64) {
        autoCompactWindow.setEstimatedPrefill(tokens)
    }

    func autoCompactWindowSnapshot() -> AutoCompactWindowSnapshot {
        autoCompactWindow.snapshot()
    }

    func claimTokenBudgetReminder() -> Bool {
        autoCompactWindow.claimTokenBudgetReminder()
    }

    func claimAutoCompactFallback() -> Bool {
        autoCompactWindow.claimAutoCompactFallback()
    }

    func autoCompactWindowNumber() -> UInt64 {
        autoCompactWindow.windowNumber
    }

    func autoCompactWindowIds() -> AutoCompactWindowIds {
        autoCompactWindow.ids
    }

    func restoreAutoCompactWindow(windowNumber: UInt64, ids: AutoCompactWindowIds) {
        autoCompactWindow.restore(windowNumber: windowNumber, ids: ids)
    }

    func advanceAutoCompactWindow() -> (UInt64, AutoCompactWindowIds) {
        autoCompactWindow.advance()
    }

    func requestNewContextWindow() {
        autoCompactWindow.requestNewContextWindow()
    }

    func takeNewContextWindowRequest() -> Bool {
        autoCompactWindow.takeNewContextWindowRequest()
    }

    func startNewContextWindow() -> (UInt64, AutoCompactWindowIds) {
        let window = autoCompactWindow.advance()
        autoCompactWindow.clearPrefill()
        return window
    }

    func tokenInfo() -> TokenUsageInfo? {
        history.tokenInfo()
    }

    func setRateLimits(_ snapshot: RateLimitSnapshot) {
        latestRateLimits = mergeRateLimitFields(previous: latestRateLimits, snapshot: snapshot)
    }

    func tokenInfoAndRateLimits() -> (TokenUsageInfo?, RateLimitSnapshot?) {
        (tokenInfo(), latestRateLimits)
    }

    func setTokenUsageFull(_ contextWindow: Int64) {
        history.setTokenUsageFull(contextWindow)
    }

    func getTotalTokenUsage(serverReasoningIncluded: Bool) -> Int64 {
        history.getTotalTokenUsage(serverReasoningIncluded: serverReasoningIncluded)
    }

    func recordMcpDependencyPrompted<S: Sequence>(_ names: S) where S.Element == String {
        mcpDependencyPrompted.formUnion(names)
    }

    func mergeConnectorSelection<S: Sequence>(_ connectorIds: S) -> Set<String> where S.Element == String {
        activeConnectorSelection.formUnion(connectorIds)
        return activeConnectorSelection
    }

    func clearConnectorSelection() {
        activeConnectorSelection.removeAll()
    }

    func queuePendingSessionStartSource(_ value: SessionStartSource) {
        pendingSessionStartSources.append(value)
    }

    func takePendingSessionStartSource() -> SessionStartSource? {
        guard !pendingSessionStartSources.isEmpty else { return nil }
        return pendingSessionStartSources.removeFirst()
    }

    func recordGrantedPermissions(
        environmentId: String,
        permissions: AdditionalPermissionProfile
    ) {
        grantedPermissionsByEnvironmentId[environmentId] = mergePermissionProfiles(
            base: grantedPermissionsByEnvironmentId[environmentId],
            permissions: permissions
        ) ?? permissions
    }

    func grantedPermissions(environmentId: String) -> AdditionalPermissionProfile? {
        grantedPermissionsByEnvironmentId[environmentId]
    }
}

func mergeRateLimitFields(
    previous: RateLimitSnapshot?,
    snapshot: RateLimitSnapshot
) -> RateLimitSnapshot {
    var merged = snapshot
    if merged.limitId == nil {
        merged.limitId = "codex"
    }
    if merged.credits == nil {
        merged.credits = previous?.credits
    }
    if merged.individualLimit == nil {
        merged.individualLimit = previous?.individualLimit
    }
    if merged.spendControlReached == nil {
        merged.spendControlReached = previous?.spendControlReached
    }
    if merged.planType == nil {
        merged.planType = previous?.planType
    }
    return merged
}
