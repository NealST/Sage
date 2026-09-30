//
//  session.swift
//  Sage
//
//  Port of codex-rs/core/src/session/session.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Session type shape plus the capture/history/token helpers `runTurn`
//  and `RegularSessionTask` need (turn started, prewarm consume, MCP
//  reprojection). The mutex/event loop still waits.
//

import CodexAsyncUtils
import CodexCore
import CodexOtel
import CodexProtocol
import Foundation

struct TurnEnvironmentSelection: Equatable, Sendable {
    var environmentId: String

    init(environmentId: String = "local") {
        self.environmentId = environmentId
    }
}

struct DynamicToolSpec: Equatable, Sendable {
    var name: String

    init(name: String) {
        self.name = name
    }
}

final class SessionConfiguration: @unchecked Sendable {
    var stepSettings: StepSettings
    var environments: [TurnEnvironmentSelection]
    var developerInstructions: String?
    var baseInstructions: String
    var allowLoginShell: Bool
    var shellEnvironmentPolicy: ShellEnvironmentPolicy
    var legacyFallbackCwd: String
    var runtimeWorkspaceRoots: [String]
    var codexHome: String
    var threadName: String?
    var disabledPluginIds: [String]
    var originalConfig: Config
    var sessionSource: SessionSource
    var parentThreadId: ThreadId?
    var forkedFromThreadId: ThreadId?
    var dynamicTools: [DynamicToolSpec]
    var trustedGuardianReviewer: Bool

    init(
        stepSettings: StepSettings = StepSettings(),
        environments: [TurnEnvironmentSelection] = [],
        developerInstructions: String? = nil,
        baseInstructions: String = "",
        allowLoginShell: Bool = false,
        shellEnvironmentPolicy: ShellEnvironmentPolicy = ShellEnvironmentPolicy(),
        legacyFallbackCwd: String = FileManager.default.currentDirectoryPath,
        runtimeWorkspaceRoots: [String] = [],
        codexHome: String = NSHomeDirectory() + "/.codex",
        threadName: String? = nil,
        disabledPluginIds: [String] = [],
        originalConfig: Config = Config(),
        sessionSource: SessionSource = .cli,
        parentThreadId: ThreadId? = nil,
        forkedFromThreadId: ThreadId? = nil,
        dynamicTools: [DynamicToolSpec] = [],
        trustedGuardianReviewer: Bool = false
    ) {
        self.stepSettings = stepSettings
        self.environments = environments
        self.developerInstructions = developerInstructions
        self.baseInstructions = baseInstructions
        self.allowLoginShell = allowLoginShell
        self.shellEnvironmentPolicy = shellEnvironmentPolicy
        self.legacyFallbackCwd = legacyFallbackCwd
        self.runtimeWorkspaceRoots = runtimeWorkspaceRoots
        self.codexHome = codexHome
        self.threadName = threadName
        self.disabledPluginIds = disabledPluginIds
        self.originalConfig = originalConfig
        self.sessionSource = sessionSource
        self.parentThreadId = parentThreadId
        self.forkedFromThreadId = forkedFromThreadId
        self.dynamicTools = dynamicTools
        self.trustedGuardianReviewer = trustedGuardianReviewer
    }

    var cwd: String { legacyFallbackCwd }
}

final class Session: @unchecked Sendable {
    var threadId: ThreadId
    var installationId: String
    var state: SessionState
    var activeTurn: ActiveTurn?
    var services: SessionServices
    var inputQueue: InputQueue
    var features: Features

    init(
        threadId: ThreadId = ThreadId(),
        installationId: String = "sage",
        configuration: SessionConfiguration = SessionConfiguration(),
        services: SessionServices = SessionServices(),
        features: Features = Features()
    ) {
        self.threadId = threadId
        self.installationId = installationId
        self.state = SessionState(sessionConfiguration: configuration)
        self.services = services
        self.inputQueue = InputQueue()
        self.features = features
    }

    func isInterrupted() -> Bool {
        activeTurn?.task?.done == true
    }

    func markMcpRuntimeDirty() {}

    func hooks() -> HookSnapshot {
        HookSnapshot()
    }

    func refreshHooks(_ config: Config) async {}

    func refreshMcpIfDirty() async {}

    func previousTurnSettingsValue() -> PreviousTurnSettings? {
        state.previousTurnSettingsValue()
    }

    func setPreviousTurnSettings(_ value: PreviousTurnSettings?) {
        state.setPreviousTurnSettings(value)
    }

    func cloneHistory() -> ContextManager {
        state.history.cloneHistory()
    }

    func recordConversationItems(
        _ turnContext: TurnContext,
        items: [ResponseItem]
    ) {
        _ = turnContext
        state.recordItems(items)
    }

    func replaceCompactedHistory(_ items: [ResponseItemEnvelope]) {
        state.replaceAnnotatedHistory(
            items,
            referenceContextItem: nil,
            replacement: .compaction(reviewerCompactionHash: nil)
        )
    }

    func recordCompletedUsage(
        _ turnContext: TurnContext,
        responseId: String,
        usage: TokenUsage?
    ) {
        guard let usage else { return }
        _ = state.recordTokenUsage(
            threadId: threadId,
            turnId: turnContext.subId,
            sessionId: turnContext.sessionId,
            rootTurnId: turnContext.subId,
            responseId: responseId,
            usage: usage
        )
        state.updateTokenInfoFromUsage(usage, modelContextWindow: turnContext.resolvedContextWindow())
        state.ensureAutoCompactWindowServerPrefillFromUsage(usage)
    }

    func takePendingHookContexts() -> [String] {
        let pending = pendingHookContexts
        pendingHookContexts = []
        return pending
    }

    func setServerReasoningIncluded(_ included: Bool) {
        state.serverReasoningIncluded = included
    }

    func getTotalTokenUsage() -> Int64 {
        state.getTotalTokenUsage(serverReasoningIncluded: state.serverReasoningIncluded)
    }

    func autoCompactWindowSnapshot() -> AutoCompactWindowSnapshot {
        state.autoCompactWindow.snapshot()
    }

    func takeNewContextWindowRequest() -> Bool {
        state.takeNewContextWindowRequest()
    }

    func currentWindowId() -> String {
        state.autoCompactWindow.ids.windowId.uuidString
    }

    func getPromptBaseInstructions() -> BaseInstructions {
        BaseInstructions(text: state.sessionConfiguration.baseInstructions)
    }

    var pendingReviewContext: PendingReviewContext?
    var exhaustedReviewBudget: ExhaustedReviewBudget?
    var emittedEvents: [EventMsg] = []
    var pendingHookContexts: [String] = []
    var sessionStartHooksConsumed = false
    var lastResponseId: String?
    var lastSafetyBuffering: SafetyBuffering?
    var lastToolCallInputDeltas: [(callId: String, delta: String)] = []
    var lastReasoningSummaryPartIndex: Int64?
    var lastRemoteCompact: CompactRemoteV2Result?
    var lastCompactModelFallback: CompactModelFallback?
    var fallbackStepContext: StepContext?
    var runCompactOverride: (([ResponseItem]) async throws -> String)?
    var startupPrewarm: SessionStartupPrewarmHandle?
    var sessionTelemetry: SessionTelemetry?
    var mcpReprojectionRequested = false
    var lastTaskAgentMessage: String?
    var lastTurnAbortReason: TurnAbortReason?
    var lastTaskError: Error?

    func emitTurnStarted(_ turnContext: TurnContext) {
        sendEvent(
            turnContext,
            .turnStarted(TurnStartedEvent(turnId: turnContext.subId, model: turnContext.model))
        )
    }

    func requestMcpRuntimeReprojection() {
        mcpReprojectionRequested = true
        services.mcpRuntime.markDirty()
    }

    func consumeStartupPrewarm(
        cancellationToken: CancellationToken
    ) async -> SessionStartupPrewarmResolution {
        if cancellationToken.isCancelled {
            return .cancelled
        }
        guard let startupPrewarm else {
            return .unavailable(status: "not_scheduled", prewarmDuration: nil)
        }
        let telemetry = sessionTelemetry ?? SessionTelemetry(
            conversationId: threadId,
            model: "gpt-5",
            slug: "gpt-5",
            originator: "sage",
            logUserPrompts: false,
            terminalType: "unknown",
            sessionSource: state.sessionConfiguration.sessionSource
        )
        return await consumeStartupPrewarmForRegularTurn(
            startupPrewarm,
            sessionTelemetry: telemetry,
            cancellationToken: cancellationToken
        )
    }

    func hasPendingGuardianReviewContext() -> Bool {
        pendingReviewContext != nil
    }

    func captureStepContext(
        _ turnContext: TurnContext,
        cancellationToken: CancellationToken
    ) throws -> StepContext {
        if cancellationToken.isCancelled {
            throw CodexErr(details: .turnAborted)
        }
        return StepContext(
            settings: StepSettings(
                model: turnContext.model,
                modelSnapshot: turnContext.captureCurrentModelInfo()
            ),
            turn: turnContext,
            environments: [turnContext.environment]
        )
    }

    func captureStepContextWithRequiredMcpServers(
        _ turnContext: TurnContext,
        cancellationToken: CancellationToken,
        requiredServers: [String],
        requiredPlugins: Set<String>
    ) throws -> StepContext {
        _ = requiredServers
        _ = requiredPlugins
        return try captureStepContext(turnContext, cancellationToken: cancellationToken)
    }

    func recordContextUpdatesAndSetReferenceContextItem(
        _ stepContext: StepContext
    ) -> WorldState {
        _ = stepContext
        return currentWorldState()
    }

    func recordStepWorldStateIfChanged(
        _ worldState: WorldState,
        _ stepContext: StepContext
    ) -> WorldState {
        _ = stepContext
        return worldState
    }

    func recordReasoningEffortOverride(_ stepContext: StepContext) {
        _ = stepContext
    }

    func mergeConnectorSelection(_ connectorIds: Set<String>) {
        _ = state.mergeConnectorSelection(connectorIds)
    }

    func emitTurnErrorLifecycle(_ turnContext: TurnContext, error: CodexErr) {
        _ = turnContext
        _ = error
    }

    func sendEvent(_ turnContext: TurnContext, _ event: EventMsg) {
        _ = turnContext
        emittedEvents.append(event)
    }

    func emitTurnItemStarted(_ turnContext: TurnContext, _ item: TurnItem) {
        sendEvent(
            turnContext,
            .itemStarted(
                ItemStartedEvent(
                    threadId: threadId,
                    turnId: turnContext.subId,
                    item: item,
                    startedAtMs: 0
                )
            )
        )
    }

    func emitTurnItemCompleted(_ turnContext: TurnContext, _ item: TurnItem) {
        sendEvent(
            turnContext,
            .itemCompleted(
                ItemCompletedEvent(
                    threadId: threadId,
                    turnId: turnContext.subId,
                    item: item,
                    startedAtMs: nil,
                    completedAtMs: 0
                )
            )
        )
    }

    func setTotalTokensFull(_ turnContext: TurnContext) {
        if let window = turnContext.resolvedContextWindow() {
            state.setTokenUsageFull(window)
        }
    }

    func updateRateLimits(_ turnContext: TurnContext, _ snapshot: RateLimitSnapshot) {
        _ = turnContext
        state.setRateLimits(snapshot)
    }

    func responsesMetadata(
        _ stepContext: StepContext,
        requestKind: CodexResponsesRequestKind
    ) -> CodexResponsesMetadata {
        var metadata = CodexResponsesMetadata(
            installationId: installationId,
            sessionId: stepContext.turn.sessionId.description,
            threadId: threadId.description,
            windowId: currentWindowId()
        )
        metadata.turnId = stepContext.turn.subId
        metadata.requestKind = requestKind
        metadata.parentThreadId = state.sessionConfiguration.parentThreadId
        metadata.subagentHeader = subagentHeaderValue(stepContext.turn.sessionSource)
        metadata.subagentKind = subagentMetadataKind(stepContext.turn.sessionSource)
        return metadata
    }

    /// Result-only test seam. Prefer `runSamplingStreamOverride` when exercising SSE.
    var runSamplingOverride:
        (([ResponseItem], StepContext) async throws -> SamplingRequestResult)?

    /// Stream-level test seam for `try_run_sampling_request`.
    var runSamplingStreamOverride: ((Prompt) async throws -> ResponseStream)?
}

struct HookSnapshot: Sendable {
    init() {}

    func matchesPluginHooks(_ sources: [String], _ warnings: [String]) -> Bool {
        true
    }
}
