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
//  reprojection). `submit` / `nextEvent` are rust `SessionIo`: a
//  dedicated loop receives Op, starts Regular/Compact tasks without
//  blocking, and publishes EventMsg. HUD cards stay out of the loop.
//  Compact queues SessionStart `compact`; `/clear` queues `clear`.
//

import CodexAPI
import CodexAsyncUtils
import CodexCore
import CodexHooks
import CodexOtel
import CodexProtocol
import CodexRollout
import Foundation

private let sessionSubmissionCapacity = 512

/// rust `tx_sub` / `rx_sub` for the app-target Session loop.
private final class SessionInbox: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [Submission] = []
    private var recvWaiters: [CheckedContinuation<Submission?, Never>] = []
    private var closed = false

    func send(_ item: Submission) -> Bool {
        lock.lock()
        if closed {
            lock.unlock()
            return false
        }
        if !recvWaiters.isEmpty {
            let waiter = recvWaiters.removeFirst()
            lock.unlock()
            waiter.resume(returning: item)
            return true
        }
        if items.count >= sessionSubmissionCapacity {
            lock.unlock()
            return false
        }
        items.append(item)
        lock.unlock()
        return true
    }

    func recv() async -> Submission? {
        lock.lock()
        if !items.isEmpty {
            let item = items.removeFirst()
            lock.unlock()
            return item
        }
        if closed {
            lock.unlock()
            return nil
        }
        return await withCheckedContinuation { continuation in
            recvWaiters.append(continuation)
            lock.unlock()
        }
    }

    func closeAndDrain() -> [Submission] {
        lock.lock()
        closed = true
        let pending = items
        items = []
        let receivers = recvWaiters
        recvWaiters = []
        lock.unlock()
        for waiter in receivers {
            waiter.resume(returning: nil)
        }
        return pending
    }
}

/// rust `tx_event` / `rx_event`.
private final class EventMailbox: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [Event] = []
    private var waiters: [CheckedContinuation<Event?, Never>] = []
    private var closed = false

    func send(_ event: Event) {
        lock.lock()
        if closed {
            lock.unlock()
            return
        }
        if !waiters.isEmpty {
            let waiter = waiters.removeFirst()
            lock.unlock()
            waiter.resume(returning: event)
            return
        }
        items.append(event)
        lock.unlock()
    }

    func recv() async -> Event? {
        lock.lock()
        if !items.isEmpty {
            let event = items.removeFirst()
            lock.unlock()
            return event
        }
        if closed {
            lock.unlock()
            return nil
        }
        return await withCheckedContinuation { continuation in
            waiters.append(continuation)
            lock.unlock()
        }
    }

    func close() {
        lock.lock()
        closed = true
        let waiters = self.waiters
        self.waiters = []
        lock.unlock()
        for waiter in waiters {
            waiter.resume(returning: nil)
        }
    }
}

struct TurnEnvironmentSelection: Equatable, Sendable {
    var environmentId: String

    init(environmentId: String = "local") {
        self.environmentId = environmentId
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
    /// Explicit user-layer files, low to high. Empty means `codexHome/config.toml`.
    var userConfigPaths: [String]
    /// Last user layer that reloaded cleanly. A failed reload leaves this in place.
    var userConfigLayer: [String: UserConfigValue]

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
        trustedGuardianReviewer: Bool = false,
        userConfigPaths: [String] = [],
        userConfigLayer: [String: UserConfigValue] = [:]
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
        self.userConfigPaths = userConfigPaths
        self.userConfigLayer = userConfigLayer
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
    let rolloutLock = NSLock()
    var rolloutRecorder: RolloutRecorder?
    private let inbox = SessionInbox()
    private let eventMailbox = EventMailbox()
    private let idleLock = NSLock()
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []
    private var loopTask: Task<Void, Never>?
    var lastSubmissionId: String?

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
        startMcpPrewarmWorker()
    }

    deinit {
        mcpPrewarmShutdown.cancel()
        mcpPrewarmRequests.close()
        mcpRefresh.close()
    }

    /// rust `Session::submit`. Starts the loop on first use.
    @discardableResult
    func submit(
        _ op: SessionOp,
        startOptions: TurnStartOptions = TurnStartOptions()
    ) async throws -> String {
        let id = UUID().uuidString
        try await submit(Submission(id: id, op: op, startOptions: startOptions))
        return id
    }

    func submit(_ submission: Submission) async throws {
        ensureSubmissionLoop()
        lastSubmissionId = submission.id
        var submission = submission
        let ack = submission.ack ?? SubmissionAck()
        submission.ack = ack
        guard inbox.send(submission) else {
            throw CodexErr.internalAgentDied
        }
        await ack.wait()
    }

    /// rust `Session::next_event`.
    func nextEvent() async throws -> Event {
        ensureSubmissionLoop()
        guard let event = await eventMailbox.recv() else {
            throw CodexErr.internalAgentDied
        }
        return event
    }

    func shutdownAndWait() async {
        ensureSubmissionLoop()
        _ = try? await submit(.shutdown)
        await loopTask?.value
    }

    func waitUntilIdle() async {
        if !hasRunningTask { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            idleLock.lock()
            if !hasRunningTask {
                idleLock.unlock()
                continuation.resume()
                return
            }
            idleWaiters.append(continuation)
            idleLock.unlock()
        }
    }

    var hasRunningTask: Bool {
        guard let task = activeTurn?.task else { return false }
        return !task.done
    }

    func ensureSubmissionLoop() {
        guard loopTask == nil, !state.shuttingDown else { return }
        loopTask = Task { [weak self] in
            await self?.runSubmissionLoop()
        }
    }

    func newTurnContext(
        subId: String? = nil,
        options: NewTurnContextOptions = NewTurnContextOptions()
    ) -> TurnContext {
        let configuration = state.sessionConfiguration
        var settings = configuration.stepSettings
        if let model = options.model {
            settings.model = model
            settings.modelSnapshot.slug = model
            settings.collaborationMode = settings.collaborationMode?.withUpdates(model: model)
        }
        if let serviceTier = options.start.serviceTier {
            settings.serviceTier = serviceTier
        }
        return TurnContext(
            subId: options.subId ?? subId ?? UUID().uuidString,
            threadId: threadId,
            cwd: configuration.legacyFallbackCwd,
            model: settings.model,
            sessionSource: configuration.sessionSource,
            config: configuration.originalConfig,
            approvalPolicy: configuration.originalConfig.approvalPolicy,
            disabledPluginIds: configuration.disabledPluginIds,
            collaborationMode: settings.collaborationMode,
            environment: TurnEnvironment(
                cwd: configuration.legacyFallbackCwd,
                workspaceRoots: configuration.runtimeWorkspaceRoots,
                temporaryDirectories: localTemporaryDirectoryPaths()
            ),
            finalOutputJsonSchema: options.start.finalOutputJsonSchema,
            cyberAccessProgram: options.start.cyberAccessProgram,
            nextStepSettings: settings,
            turnTrigger: options.start.turnTrigger,
            parentTurnId: options.start.parentTurnId,
            rootTurnId: options.start.rootTurnId,
            responsesapiClientMetadata: options.responsesapiClientMetadata,
            initiatingAgentPath: options.initiatingAgentPath,
            dynamicTools: configuration.dynamicTools
        )
    }

    func submissionInboxRecv() async -> Submission? {
        await inbox.recv()
    }

    func submissionInboxCloseAndDrain() -> [Submission] {
        inbox.closeAndDrain()
    }

    func closeEventMailbox() {
        eventMailbox.close()
    }

    func isInterrupted() -> Bool {
        activeTurn?.task?.done == true
    }

    func hooks() -> HookSnapshot {
        HookSnapshot(afterAgent: services.afterAgentHooks)
    }

    func refreshHooks(_ config: Config) async {}

    /// rust `Session::has_outstanding_durable_sleep`.
    func hasOutstandingDurableSleep() -> Bool {
        services.outstandingDurableSleep
    }

    /// rust `Session::reference_context_item` cyber program.
    func referenceCyberAccessProgram() -> CyberAccessProgram? {
        state.history.referenceContextItemValue()?.cyberAccessProgram
    }

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
        state.queuePendingSessionStartSource(.compact)
    }

    /// rust `/clear`: drop history and queue SessionStart `clear`.
    func replaceResetHistory(_ items: [ResponseItemEnvelope] = []) {
        state.replaceAnnotatedHistory(
            items,
            referenceContextItem: nil,
            replacement: .reset
        )
        state.queuePendingSessionStartSource(.clear)
    }

    func queuePendingSessionStartSource(_ value: SessionStartSource) {
        state.queuePendingSessionStartSource(value)
    }

    func takePendingSessionStartSource() -> SessionStartSource? {
        state.takePendingSessionStartSource()
    }

    func hasPendingSessionStartSource() -> Bool {
        !state.pendingSessionStartSources.isEmpty
    }

    func advanceAutoCompactWindow() -> (UInt64, AutoCompactWindowIds) {
        state.advanceAutoCompactWindow()
    }

    func startNewContextWindow() -> (UInt64, AutoCompactWindowIds) {
        state.startNewContextWindow()
    }

    func recordCompletedUsage(
        _ turnContext: TurnContext,
        responseId: String,
        usage: CodexProtocol.TokenUsage?
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

    func enqueuePendingHookContexts(_ contexts: [String]) {
        pendingHookContexts.append(contentsOf: contexts)
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
    var stopHookActive = false
    var lastResponseId: String?
    var lastSafetyBuffering: SafetyBuffering?
    var lastToolCallInputDeltas: [(callId: String, delta: String)] = []
    var lastReasoningSummaryPartIndex: Int64?
    var lastRemoteCompact: CompactRemoteV2Result?
    var lastCompactCheckpoint: CompactionCheckpointMetadata?
    var lastCompactModelFallback: CompactModelFallback?
    var fallbackStepContext: StepContext?
    var runCompactOverride: (([ResponseItem]) async throws -> String)?
    var startupPrewarm: SessionStartupPrewarmHandle?
    var sessionTelemetry: SessionTelemetry?
    var mcpReprojectionRequested = false
    let mcpRefresh = McpRefresh()
    let mcpPrewarmRequests = McpPrewarmRequests()
    let mcpPrewarmShutdown = CancellationToken()
    var mcpPrewarmTask: Task<Void, Never>?
    /// rust `mcp_prewarm_tx` slot. True while a request is queued and the
    /// worker has not received it yet.
    var mcpPrewarmRequested: Bool { mcpPrewarmRequests.isPending }
    /// Stand-ins for `skills_service.clear_cache` and `plugins_manager.clear_cache`.
    var skillsCacheGeneration: UInt64 = 0
    var pluginsCacheGeneration: UInt64 = 0
    var lastTaskAgentMessage: String?
    var lastStartedTurnContext: TurnContext?
    /// Rust `last_started_turn_id`. Cleared by a standalone settings update so
    /// it no longer continues that turn. The context itself stays for tests
    /// and the running turn.
    var lastStartedTurnId: String?
    /// Reply for the latest `Op::TurnSettings`. The submission loop is serial,
    /// so the ack is not signaled until this is stored.
    var lastTurnSettingsOutcome: TurnSettingsUpdateOutcome?
    /// Decision for the latest `Op::InterruptIfNoPendingInput`. `true` means
    /// the named turn was taken for abort. Stored before the abort runs.
    var lastInterruptIfNoPendingInput: Bool?
    /// Reply for the latest `Op::RecoverTurn`. An invalid settings override
    /// leaves this nil and sets `lastTurnInputError` instead.
    var lastTurnInputSubmission: TurnInputSubmission?
    var lastTurnInputError: String?
    /// Reply for the latest `Op::SuspendTurnAndShutdown`. A non-root thread
    /// leaves this nil and sets `lastSuspendTurnError` instead.
    var lastSuspendTurnOutcome: SuspendTurnOutcome?
    var lastSuspendTurnError: String?
    /// Next `reserve_input_order` value. Legacy guardian mode does not consume it.
    var nextUserInputOrder: UInt64 = 0
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
        markMcpRuntimeDirty()
        scheduleMcpPrewarm()
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
    ) async throws -> StepContext {
        if cancellationToken.isCancelled {
            throw CodexErr(details: .turnAborted)
        }
        await refreshMcpIfDirty()
        // Subsequent steps read the published settings. An earlier `StepContext`
        // keeps the binding it captured, so a later publish does not rewrite it.
        return StepContext(
            settings: turnContext.nextStepSettings,
            turn: turnContext,
            environments: [turnContext.environment],
            mcp: services.mcpRuntime.currentBinding
        )
    }

    func captureStepContextWithRequiredMcpServers(
        _ turnContext: TurnContext,
        cancellationToken: CancellationToken,
        requiredServers: [String],
        requiredPlugins: Set<String>
    ) async throws -> StepContext {
        _ = requiredServers
        _ = requiredPlugins
        return try await captureStepContext(turnContext, cancellationToken: cancellationToken)
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
        let id = turnContext.subId.isEmpty ? (lastSubmissionId ?? "") : turnContext.subId
        sendEventRaw(Event(id: id, msg: event))
    }

    func sendEventRaw(_ event: Event) {
        emittedEvents.append(event.msg)
        eventMailbox.send(event)
    }

    func notifyIdleIfNeeded() {
        guard !hasRunningTask else { return }
        idleLock.lock()
        let waiters = idleWaiters
        idleWaiters = []
        idleLock.unlock()
        for waiter in waiters {
            waiter.resume()
        }
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

    /// rust `request_guardian_approval` for `request_permissions`.
    /// `nil` falls through to the user card, which is the user reviewer.
    /// A decision is applied inside `requestPermissions` and does not emit
    /// `RequestPermissions`.
    var requestPermissionsGuardian:
        (@Sendable (RequestPermissionsArgs) async -> CodexProtocol.ReviewDecision?)?

    /// Result-only test seam. Prefer `runSamplingStreamOverride` when exercising SSE.
    var runSamplingOverride:
        (([ResponseItem], StepContext) async throws -> SamplingRequestResult)?

    /// Stream-level test seam for `try_run_sampling_request`.
    var runSamplingStreamOverride: ((Prompt) async throws -> CodexCore.ResponseStream)?

    /// Set for the duration of `runSamplingStreamOverride`. Live Execute
    /// streams through this session instead of opening another one.
    var samplingClientSession: ModelClientSession?
    var samplingStepContext: StepContext?
    /// Fills base instructions and tool schemas before `buildPrompt`.
    var prepareSamplingPrompt: (@MainActor () async -> Void)?
}

struct HookSnapshot: Sendable {
    var afterAgent: [Hook]

    init(afterAgent: [Hook] = []) {
        self.afterAgent = afterAgent
    }

    func matchesPluginHooks(_ sources: [String], _ warnings: [String]) -> Bool {
        true
    }

    /// rust `Hooks::dispatch` for AfterAgent only. ClaudeHooksEngine stays off.
    func dispatch(_ hookPayload: HookPayload) async -> [HookResponse] {
        var outcomes: [HookResponse] = []
        outcomes.reserveCapacity(afterAgent.count)
        for hook in afterAgent {
            let outcome = await hook.execute(hookPayload)
            outcomes.append(outcome)
            if outcome.result.shouldAbortOperation { break }
        }
        return outcomes
    }
}
