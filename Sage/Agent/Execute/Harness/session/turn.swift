//
//  turn.swift
//  Sage
//
//  Port of codex-rs/core/src/session/turn.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  `runTurn` ports the rust control flow: guardian gate, pre-sampling
//  compact, MCP mention collection, skill/plugin injection, guardian
//  finalize/check_prompt, then sample → tool dispatch / incremental
//  text (plan-mode) / token usage / local auto-compact / time reminder
//  / mailbox preempt / SSE metadata / itemCompleted / remote compact.
//  MCP specs decode catalog JSON schema via parseCatalogParameters.
//  Apps visibility/policy/agent-plugin budgets come from mcp_tool_exposure.
//  Sage execute tools register through sage_execute / onSageToolCall.
//  Live Execute calls `runTurn` when `useHarnessRunTurn`. Tool calls stay
//  in the sampling stream and dispatch here. HUD admission happens before
//  the stream is built, so a card pauses the turn instead of waiting inside it.
//

import CodexAPI
import CodexAsyncUtils
import CodexCore
import CodexModelProviderInfo
import CodexProtocol
import CodexThreadStore
import CodexUtils
import Foundation

/// Shared sample → tools → sample loop. `RegularTask` and `ExploreTask` both use it.
@MainActor
protocol ExecuteTurnLoop: AnyObject {
    var canOfferMoreTools: Bool { get }
    /// Compact, then connect MCP servers, before this sample. Tool hooks run in `consume`.
    func willSample(includeTools: Bool) async
    func sample(includeTools: Bool) async throws -> ModelTurn
    func consume(_ turn: ModelTurn) async -> Turn.StepResult
    func didCancel() async
    func didFail(_ error: Error) async
    func pauseForToolRoundLimit() async
}

enum Turn {
    enum StepResult {
        /// Final answer, approval pause, safety valve, or a failed persist.
        case finished
        /// Tool output is in the transcript. Sample again.
        case needsFollowUp
    }

    @MainActor
    static func run(_ task: some ExecuteTurnLoop, includeTools: Bool) async {
        var includeTools = includeTools
        while !Task.isCancelled {
            await task.willSample(includeTools: includeTools)
            let turn: ModelTurn
            do {
                try Task.checkCancellation()
                turn = try await task.sample(includeTools: includeTools)
                try Task.checkCancellation()
            } catch is CancellationError {
                await task.didCancel()
                return
            } catch {
                await task.didFail(error)
                return
            }

            switch await task.consume(turn) {
            case .finished:
                return
            case .needsFollowUp:
                includeTools = true
                guard task.canOfferMoreTools else {
                    await task.pauseForToolRoundLimit()
                    return
                }
            }
        }
    }
}

/// Explicit MCP startup requirements retained across restarts within one user turn.
struct McpStartupRequirements: Equatable, Sendable {
    var requiredServers: [String]
    var requiredPlugins: Set<String>

    init(requiredServers: [String] = [], requiredPlugins: Set<String> = []) {
        self.requiredServers = requiredServers
        self.requiredPlugins = requiredPlugins
    }
}

struct PreparedToolRecommendations: Equatable, Sendable {
    var authPresent: Bool
    var endpointCandidateCount: Int

    init(authPresent: Bool = false, endpointCandidateCount: Int = 0) {
        self.authPresent = authPresent
        self.endpointCandidateCount = endpointCandidateCount
    }
}

struct SamplingRequestResult: Equatable, Sendable {
    var needsFollowUp: Bool
    var lastAgentMessage: String?

    init(needsFollowUp: Bool, lastAgentMessage: String? = nil) {
        self.needsFollowUp = needsFollowUp
        self.lastAgentMessage = lastAgentMessage
    }
}

/// Takes initial turn input and runs a loop where, at each sampling request,
/// the model replies with either requested function calls or an assistant message.
func runTurn(
    sess: Session,
    turnContext: TurnContext,
    input: inout [SessionTurnInput],
    mcpStartupRequirements: inout McpStartupRequirements,
    prewarmedClientSession: ModelClientSession?,
    cancellationToken: CancellationToken
) async throws -> String? {
    if Guardian.isBasicSessionSource(turnContext.sessionSource) {
        try checkPendingGuardianInput(sess: sess, turnContext: turnContext)
    }

    drainAsyncHookResults(sess: sess, turnContext: turnContext, beforeUserPrompt: true)

    var clientSession = prewarmedClientSession ?? sess.services.modelClient?.newSession()
    do {
        try await runPreSamplingCompact(
            sess: sess,
            turnContext: turnContext,
            clientSession: &clientSession,
            cancellationToken: cancellationToken
        )
    } catch {
        let err = (error as? CodexErr) ?? CodexErr.fatal(String(describing: error))
        _ = await runHooksAndRecordInputs(
            sess: sess,
            turnContext: turnContext,
            modelInfo: turnContext.captureCurrentModelInfo(),
            input: input,
            persistContext: .standard
        )
        if err.details == .turnAborted || isToolCollision(err) {
            throw err
        }
        sess.emitTurnErrorLifecycle(turnContext, error: err)
        sess.sendEvent(turnContext, .error(ErrorEvent(message: err.localizedDescription)))
        return nil
    }

    let userInput = turnUserInput(input)
    let allowPluginMentions = !Guardian.isBasicSessionSource(turnContext.sessionSource)
    if allowPluginMentions {
        mcpStartupRequirements.requiredPlugins.formUnion(collectExplicitPluginIds(userInput))
    }

    if cancellationToken.isCancelled {
        _ = await runHooksAndRecordInputs(
            sess: sess,
            turnContext: turnContext,
            modelInfo: turnContext.captureCurrentModelInfo(),
            input: input,
            persistContext: .standard
        )
        throw CodexErr(details: .turnAborted)
    }

    let (inputRequiredServers, mentionedPlugins) = requiredMcpServersForInput(
        sess: sess,
        turnContext: turnContext,
        userInput: userInput
    )
    mcpStartupRequirements.requiredServers.append(contentsOf: inputRequiredServers)
    mcpStartupRequirements.requiredServers.sort()
    mcpStartupRequirements.requiredServers = uniquedPreservingOrder(mcpStartupRequirements.requiredServers)

    let firstStepContext: StepContext
    do {
        firstStepContext = try sess.captureStepContextWithRequiredMcpServers(
            turnContext,
            cancellationToken: cancellationToken,
            requiredServers: mcpStartupRequirements.requiredServers,
            requiredPlugins: mcpStartupRequirements.requiredPlugins
        )
    } catch {
        let err = (error as? CodexErr) ?? CodexErr.fatal(String(describing: error))
        if err.details == .turnAborted {
            _ = await runHooksAndRecordInputs(
                sess: sess,
                turnContext: turnContext,
                modelInfo: turnContext.captureCurrentModelInfo(),
                input: input,
                persistContext: .standard
            )
        }
        throw err
    }

    let cwdRelative = turnContext.config.features.enabled(.cwdRelativeTurnDiffs)
        || sess.features.enabled(.cwdRelativeTurnDiffs)
    let displayRoots: [(String, String)]
    if cwdRelative {
        displayRoots = firstStepContext.environments.map { ($0.environmentId, $0.cwd) }
    } else {
        displayRoots = turnDiffDisplayRoots(firstStepContext)
    }
    _ = displayRoots

    var worldState = sess.recordContextUpdatesAndSetReferenceContextItem(firstStepContext)

    guard let (injectionItems, explicitlyEnabledConnectors) = await buildSkillsAndPlugins(
        sess: sess,
        stepContext: firstStepContext,
        userInput: userInput,
        mentionedPlugins: mentionedPlugins,
        cancellationToken: cancellationToken
    ) else {
        return nil
    }

    if await runPendingSessionStartHooks(sess: sess, turnContext: turnContext) {
        return nil
    }

    if Guardian.isBasicSessionSource(turnContext.sessionSource) {
        try finalizeGuardianInput(sess: sess, stepContext: firstStepContext, input: &input)
    }

    var canDrainPendingInput = input.isEmpty
    if await runHooksAndRecordInputs(
        sess: sess,
        turnContext: turnContext,
        modelInfo: firstStepContext.settings.modelSnapshot,
        input: input,
        persistContext: .turnStart
    ) {
        return nil
    }

    sess.mergeConnectorSelection(explicitlyEnabledConnectors)
    sess.setPreviousTurnSettings(
        PreviousTurnSettings(
            model: turnContext.model,
            compHash: turnContext.modelCompHash,
            realtimeActive: turnContext.realtimeActive,
            contextWindow: turnContext.resolvedContextWindow()
        )
    )
    for responseItem in injectionItems {
        sess.recordConversationItems(turnContext, items: [responseItem])
    }

    var lastAgentMessage: String?
    var nextStepContext: StepContext? = firstStepContext
    var turnDiffTracker = TurnDiffTracker()
    _ = turnDiffTracker

    while true {
        if cancellationToken.isCancelled {
            throw CodexErr(details: .turnAborted)
        }

        let pendingInput: [SessionTurnInput]
        if canDrainPendingInput {
            pendingInput = sess.inputQueue.getPendingInput(sess.activeTurn)
        } else {
            pendingInput = []
        }

        if await runHooksAndRecordInputs(
            sess: sess,
            turnContext: turnContext,
            modelInfo: turnContext.captureCurrentModelInfo(),
            input: pendingInput,
            persistContext: .steeredUserInput
        ) {
            break
        }

        let stepContext: StepContext
        if let ready = nextStepContext, pendingInput.isEmpty {
            nextStepContext = nil
            stepContext = ready
        } else if nextStepContext == nil, pendingInput.isEmpty {
            stepContext = try sess.captureStepContextWithRequiredMcpServers(
                turnContext,
                cancellationToken: cancellationToken,
                requiredServers: mcpStartupRequirements.requiredServers,
                requiredPlugins: mcpStartupRequirements.requiredPlugins
            )
        } else {
            let pendingUserInput = turnUserInput(pendingInput)
            if allowPluginMentions {
                mcpStartupRequirements.requiredPlugins.formUnion(collectExplicitPluginIds(pendingUserInput))
            }
            let (pendingRequiredServers, _) = requiredMcpServersForInput(
                sess: sess,
                turnContext: turnContext,
                userInput: pendingUserInput
            )
            mcpStartupRequirements.requiredServers.append(contentsOf: pendingRequiredServers)
            mcpStartupRequirements.requiredServers.sort()
            mcpStartupRequirements.requiredServers = uniquedPreservingOrder(
                mcpStartupRequirements.requiredServers
            )
            stepContext = try sess.captureStepContextWithRequiredMcpServers(
                turnContext,
                cancellationToken: cancellationToken,
                requiredServers: mcpStartupRequirements.requiredServers,
                requiredPlugins: mcpStartupRequirements.requiredPlugins
            )
        }

        worldState = sess.recordStepWorldStateIfChanged(worldState, stepContext)
        sess.recordReasoningEffortOverride(stepContext)
        try maybeRecordCurrentTimeReminder(
            sess: sess,
            turnContext: turnContext,
            windowId: sess.currentWindowId()
        )

        let samplingRequestInput = sess.cloneHistory().forPrompt()
        let samplingResult: SamplingRequestResult
        do {
            samplingResult = try await runSamplingRequest(
                sess: sess,
                stepContext: stepContext,
                clientSession: &clientSession,
                input: samplingRequestInput,
                cancellationToken: cancellationToken.childToken()
            )
        } catch {
            let err = (error as? CodexErr) ?? CodexErr.fatal(String(describing: error))
            if err.details == .turnAborted || err.details == .contextWindowExceeded {
                throw err
            }
            sess.emitTurnErrorLifecycle(turnContext, error: err)
            sess.sendEvent(turnContext, .error(ErrorEvent(message: err.localizedDescription)))
            break
        }

        if samplingResult.needsFollowUp {
            sess.inputQueue.acceptMailboxDeliveryForCurrentTurn(sess.activeTurn, subId: turnContext.subId)
        }
        canDrainPendingInput = true
        drainAsyncHookResults(sess: sess, turnContext: turnContext, beforeUserPrompt: false)

        let hasPendingInput = sess.inputQueue.hasPendingInput(sess.activeTurn)
        let tokenStatus = contextWindowTokenStatus(sess: sess, turnContext: turnContext)
        let needsFollowUp = samplingResult.needsFollowUp || hasPendingInput
        let tokenLimitReached = tokenStatus.tokenLimitReached
        let shouldRollOver = needsFollowUp && (sess.takeNewContextWindowRequest() || tokenLimitReached)

        if shouldRollOver {
            try await runAutoCompact(
                sess: sess,
                stepContext: stepContext,
                clientSession: &clientSession,
                injection: .beforeLastUserMessage
            )
            if await runPendingSessionStartHooks(sess: sess, turnContext: turnContext) {
                return nil
            }
            canDrainPendingInput = !samplingResult.needsFollowUp
            nextStepContext = nil
            continue
        }

        if !needsFollowUp {
            lastAgentMessage = samplingResult.lastAgentMessage
            break
        }

        nextStepContext = nil
    }

    if cancellationToken.isCancelled {
        throw CodexErr(details: .turnAborted)
    }
    return lastAgentMessage
}

func runHooksAndRecordInputs(
    sess: Session,
    turnContext: TurnContext,
    modelInfo: TurnModelSnapshot,
    input: [SessionTurnInput],
    persistContext: PersistContext
) async -> Bool {
    _ = modelInfo
    if sess.hasPendingGuardianReviewContext() {
        return false
    }
    var blockedInput = false
    var acceptedUserInput = false
    let projectRoot = URL(fileURLWithPath: turnContext.cwd, isDirectory: true)
    for inputItem in input {
        let hookOutcome = await inspectPendingInput(inputItem, projectRoot: projectRoot)
        if hookOutcome.shouldStop {
            blockedInput = true
            recordAdditionalContexts(sess: sess, turnContext: turnContext, contexts: hookOutcome.additionalContexts)
        } else {
            if case .userInput(let content, _, _) = inputItem, !content.isEmpty {
                acceptedUserInput = true
            }
            var itemPersist = persistContext
            if persistContext == .steeredUserInput, case .functionCallOutput = inputItem {
                itemPersist = .standard
            }
            recordPendingInput(
                sess: sess,
                turnContext: turnContext,
                inputItem: inputItem,
                additionalContexts: hookOutcome.additionalContexts,
                persistContext: itemPersist
            )
        }
    }
    return blockedInput && !acceptedUserInput
}

func turnUserInput(_ input: [SessionTurnInput]) -> [UserInput] {
    input.flatMap { item -> [UserInput] in
        switch item {
        case .userInput(let content, _, _):
            return content
        case .responseItem, .functionCallOutput, .interAgentCommunication:
            return []
        }
    }
}

func getLastAssistantMessageFromTurn(_ responses: [ResponseItem]) -> String? {
    getLastAssistantMessage(from: responses)
}

/// Returns true only when both turns declare compaction compatibility hashes and they differ.
func compHashChanged(previous: String?, current: String?) -> Bool {
    guard let previous, let current else { return false }
    return previous != current
}

func buildPrompt(
    input: [ResponseItem],
    stepContext: StepContext,
    baseInstructions: BaseInstructions,
    sess: Session? = nil
) -> Prompt {
    let turnContext = stepContext.turn
    let tools = builtTools(sess: sess, stepContext: stepContext)
    let parallelToolCalls = sess?.services.sageResponsesTools == nil || !tools.isEmpty
    return Prompt(
        input: input,
        tools: tools,
        parallelToolCalls: parallelToolCalls,
        baseInstructions: baseInstructions,
        outputSchema: nil,
        outputSchemaStrict: !Guardian.isBasicSessionSource(turnContext.sessionSource),
        cyberAccessProgram: nil
    )
}

func prepareToolRecommendations(sess: Session, turnContext: TurnContext) -> PreparedToolRecommendations {
    _ = turnContext
    return PreparedToolRecommendations(
        authPresent: sess.services.modelClient != nil,
        endpointCandidateCount: sess.services.availablePlugins.count
    )
}

func toolRouterPlanOptions(sess: Session?, turnContext: TurnContext) -> ToolRouterPlanOptions {
    var options = ToolRouterPlanOptions()
    let features = turnContext.config.features
    let sessionFeatures = sess?.features
    options.includeExecCommand = features.enabled(.unifiedExec)
        || sessionFeatures?.enabled(.unifiedExec) == true
    options.includeWriteStdin = options.includeExecCommand
    options.includeMcpResources = !(sess?.services.mcpTools.isEmpty ?? true)
    return options
}

func assembleToolRouter(sess: Session?, stepContext: StepContext) -> ToolRouter {
    if let existing = stepContext.toolRouter {
        return existing
    }
    let options = toolRouterPlanOptions(sess: sess, turnContext: stepContext.turn)
    var router = finalizeToolRouter(options)
    let mcpTools = mcpVisibleTools(from: sess)
    let registrations: [McpToolRegistration]
    if let sess {
        registrations = sess.services.mcpHandlerCache.registerTools(
            mcpTools,
            bindingID: sess.services.mcpBindingID,
            appsEnabled: sess.services.appsEnabled,
            appsConfig: sess.services.appsPolicy,
            searchToolEnabled: options.includeToolSearch
        )
    } else {
        registrations = appendMcpTools(
            mcpTools,
            appsEnabled: true,
            appsConfig: nil,
            searchToolEnabled: options.includeToolSearch
        )
    }
    registerMcpTools(registrations, on: &router)
    if let sess {
        registerSageTools(sess.services.sageToolNames, on: &router)
    }
    stepContext.toolRouter = router
    return router
}

func builtTools(stepContext: StepContext) -> [CodexProtocol.JSONValue] {
    builtTools(sess: nil, stepContext: stepContext)
}

func jsonSchema(forMCP tool: McpVisibleTool) -> JsonSchema {
    guard let raw = tool.parametersJSON else {
        return .object([:], additionalProperties: false)
    }
    return (try? parseCatalogParameters(raw)) ?? .object([:], additionalProperties: false)
}

func mcpToolSpec(_ tool: McpVisibleTool) -> ToolSpec {
    .function(
        ResponsesApiTool(
            name: tool.name,
            description: tool.description,
            strict: false,
            parameters: jsonSchema(forMCP: tool)
        )
    )
}

func registerMcpTools(_ registrations: [McpToolRegistration], on router: inout ToolRouter) {
    var existing = Set(router.registry.registeredEntries().map { flatToolName($0.runtime.toolName()) })
    existing.formUnion(router.modelVisibleSpecs.map { $0.name() })
    for registration in registrations {
        guard !existing.contains(registration.tool.name) else { continue }
        existing.insert(registration.tool.name)
        let spec = mcpToolSpec(registration.tool)
        let exposure = toolExposure(registration.exposure)
        router.registry.register(
            McpHandler(
                name: ToolName(plain: registration.tool.name),
                spec: spec,
                serverName: registration.tool.serverName,
                exposure: exposure
            ),
            exposure: exposure
        )
        if exposure != .hidden {
            router.modelVisibleSpecs.append(spec)
        }
    }
}

func toolExposure(_ exposure: McpToolExposure) -> ToolExposure {
    switch exposure {
    case .direct: return .direct
    case .deferred: return .deferred
    case .hidden: return .hidden
    }
}

func mcpVisibleTools(from sess: Session?) -> [McpVisibleTool] {
    guard let sess else { return [] }
    if !sess.services.mcpVisibleTools.isEmpty {
        return sess.services.mcpVisibleTools
    }
    return sess.services.modelVisibleMcpToolNames.map { McpVisibleTool(name: $0) }
}

func builtTools(sess: Session?, stepContext: StepContext) -> [CodexProtocol.JSONValue] {
    let router = assembleToolRouter(sess: sess, stepContext: stepContext)
    if let tools = sess?.services.sageResponsesTools {
        return tools
    }
    return router.modelVisibleSpecs.map { spec in
        .object(["name": .string(spec.name())])
    }
}

func turnDiffDisplayRoots(_ stepContext: StepContext) -> [(String, String)] {
    stepContext.environments.map { environment in
        (environment.environmentId, environment.cwd)
    }
}

func requiredMcpServersForInput(
    sess: Session,
    turnContext: TurnContext,
    userInput: [UserInput]
) -> ([String], [PluginCapabilitySummary]) {
    if Guardian.isBasicSessionSource(turnContext.sessionSource) {
        return ([], [])
    }
    let plugins = sess.services.availablePlugins.filter {
        !turnContext.disabledPluginIds.contains($0.configName)
    }
    return requiredMcpServersAndMentionedPlugins(
        userInput: userInput,
        plugins: plugins,
        skills: sess.services.skillsLookup,
        connectors: sess.services.availableConnectors
    )
}

func buildSkillsAndPlugins(
    sess: Session,
    stepContext: StepContext,
    userInput: [UserInput],
    mentionedPlugins: [PluginCapabilitySummary],
    cancellationToken: CancellationToken
) async -> ([ResponseItem], Set<String>)? {
    if cancellationToken.isCancelled {
        return nil
    }
    if Guardian.isBasicSessionSource(stepContext.turn.sessionSource) {
        return ([], [])
    }
    let built = buildSkillAndPluginInjectionItems(
        userInput: userInput,
        mentionedPlugins: mentionedPlugins,
        skills: sess.services.skillsLookup,
        mcpTools: sess.services.mcpTools,
        connectors: sess.services.availableConnectors
    )
    for warning in built.warnings {
        sess.sendEvent(stepContext.turn, .error(ErrorEvent(message: warning)))
    }
    let extensionItems = await buildExtensionTurnInputItems(
        sess: sess,
        stepContext: stepContext,
        userInput: userInput,
        cancellationToken: cancellationToken
    )
    var items = built.items
    items.append(contentsOf: extensionItems)
    return (items, built.connectors)
}

func buildExtensionTurnInputItems(
    sess: Session,
    stepContext: StepContext,
    userInput: [UserInput],
    cancellationToken: CancellationToken
) async -> [ResponseItem] {
    if cancellationToken.isCancelled {
        return []
    }
    let contributors = sess.services.turnInputContributors
    guard !contributors.isEmpty else { return [] }
    var items: [ResponseItem] = []
    for contributor in contributors {
        if cancellationToken.isCancelled {
            return []
        }
        items.append(contentsOf: await contributor.contribute(
            userInput: userInput,
            turnId: stepContext.turn.subId
        ))
    }
    return items
}

func runPreSamplingCompact(
    sess: Session,
    turnContext: TurnContext,
    clientSession: inout ModelClientSession?,
    cancellationToken: CancellationToken
) async throws {
    try await maybeRunPreviousModelInlineCompact(
        sess: sess,
        turnContext: turnContext,
        clientSession: &clientSession,
        cancellationToken: cancellationToken
    )
    let tokenStatus = contextWindowTokenStatus(sess: sess, turnContext: turnContext)
    if tokenStatus.tokenLimitReached {
        let stepContext = try sess.captureStepContext(turnContext, cancellationToken: cancellationToken)
        try await runAutoCompact(
            sess: sess,
            stepContext: stepContext,
            clientSession: &clientSession,
            injection: .beforeLastUserMessage
        )
    }
}

func maybeRunPreviousModelInlineCompact(
    sess: Session,
    turnContext: TurnContext,
    clientSession: inout ModelClientSession?,
    cancellationToken: CancellationToken
) async throws {
    guard let previous = sess.previousTurnSettingsValue() else { return }
    let shouldCompactForCompHashChange = compHashChanged(
        previous: previous.compHash,
        current: turnContext.modelCompHash
    )
    if !shouldCompactForCompHashChange, previous.model == turnContext.model {
        return
    }
    if cancellationToken.isCancelled {
        throw CodexErr(details: .turnAborted)
    }
    if shouldCompactForCompHashChange {
        let stepContext = try sess.captureStepContext(turnContext, cancellationToken: cancellationToken)
        try await runAutoCompact(
            sess: sess,
            stepContext: stepContext,
            clientSession: &clientSession,
            injection: .beforeLastUserMessage
        )
        return
    }
    guard previous.model != turnContext.model,
          let oldWindow = previous.contextWindow,
          let newWindow = turnContext.resolvedContextWindow(),
          oldWindow > newWindow
    else {
        return
    }
    let activeTokens = sess.getTotalTokenUsage()
    let previousModelLimitReached: Bool
    switch turnContext.config.modelAutoCompactTokenLimitScope {
    case .total:
        let limit = turnContext.autoCompactTokenLimit() ?? Int64.max
        previousModelLimitReached = activeTokens > limit || activeTokens >= newWindow
    case .bodyAfterPrefix:
        previousModelLimitReached = activeTokens >= newWindow
    }
    if previousModelLimitReached {
        let stepContext = try sess.captureStepContext(turnContext, cancellationToken: cancellationToken)
        try await runAutoCompact(
            sess: sess,
            stepContext: stepContext,
            clientSession: &clientSession,
            injection: .beforeLastUserMessage
        )
    }
}

func runAutoCompact(
    sess: Session,
    stepContext: StepContext,
    clientSession: inout ModelClientSession?,
    injection: InitialContextInjection
) async throws {
    if sess.features.enabled(.tokenBudget) {
        try await runInlineTokenBudgetCompact(
            sess: sess,
            stepContext: stepContext,
            injection: injection
        )
        return
    }
    _ = clientSession
    let projectRoot = URL(fileURLWithPath: stepContext.turn.cwd, isDirectory: true)
    let preCompact = await HookRuntime.preCompact(projectRoot: projectRoot)
    if preCompact.shouldStop {
        throw CodexErr(details: .turnAborted)
    }
    recordAdditionalContexts(
        sess: sess,
        turnContext: stepContext.turn,
        contexts: preCompact.additionalContexts
    )

    let history = sess.cloneHistory()
    var summary = getLastAssistantMessageFromTurn(history.forPrompt()) ?? ""
    var usedRemote = false
    if let remote = try await runRemoteCompactV2(
        sess: sess,
        stepContext: stepContext,
        clientSession: &clientSession,
        history: history.forPrompt()
    ) {
        summary = remote
        usedRemote = true
    } else if let override = sess.runCompactOverride {
        summary = try await override(history.forPrompt())
    }
    let compacted: [ResponseItemEnvelope]
    if usedRemote {
        compacted = buildV2CompactedHistory(
            promptInput: history.items,
            compactionOutput: wrapCompactionSummary(summary),
            imageBudget: stepContext.turn.config.features.enabled(.unifiedImageBudget)
                || sess.features.enabled(.unifiedImageBudget)
                ? .enabled
                : .disabled
        )
    } else {
        compacted = buildCompactedHistory(
            initialContext: [],
            userMessages: collectAnnotatedUserMessages(history.items),
            summaryText: summary
        )
    }
    let (windowNumber, _) = sess.advanceAutoCompactWindow()
    let historyWithContext = applyCompactedHistoryInitialContext(
        compacted,
        sess: sess,
        stepContext: stepContext,
        injection: injection
    )
    sess.replaceCompactedHistory(historyWithContext)
    sess.lastCompactCheckpoint = CompactionCheckpointMetadata(
        windowNumber: windowNumber,
        summary: summary
    )
    sess.lastRemoteCompact = CompactRemoteV2Result(summary: summary, succeeded: usedRemote || sess.runCompactOverride != nil)
    sess.sendEvent(stepContext.turn, .contextCompacted(ContextCompactedEvent()))

    let postCompact = await HookRuntime.postCompact(projectRoot: projectRoot)
    if postCompact.shouldStop {
        throw CodexErr(details: .turnAborted)
    }
    recordAdditionalContexts(
        sess: sess,
        turnContext: stepContext.turn,
        contexts: postCompact.additionalContexts
    )
}

func runRemoteCompactV2(
    sess: Session,
    stepContext: StepContext,
    clientSession: inout ModelClientSession?,
    history: [ResponseItem]
) async throws -> String? {
    if let override = sess.runCompactOverride {
        return try await override(history)
    }
    guard let clientSession else { return nil }
    let prompt = Prompt(
        input: history,
        tools: [],
        parallelToolCalls: false,
        baseInstructions: BaseInstructions(text: compactSummaryPrefix),
        outputSchema: nil,
        outputSchemaStrict: false,
        cyberAccessProgram: nil
    )
    var retryState = ResponsesStreamRetryState()
    let maxRetries = min(
        clientSession.client.providerInfo.streamMaxRetries(),
        maxRemoteCompactionV2StreamRetries
    )
    func streamOnce(_ active: StepContext) async throws -> String {
        let stream = try await clientSession.stream(
            prompt: prompt,
            modelInfo: active.turn.modelInfoValue(),
            responsesMetadata: sess.responsesMetadata(
                active,
                requestKind: .compaction(
                    CompactionTurnMetadata(
                        trigger: .auto,
                        reason: .contextWindow,
                        implementation: .remoteV2,
                        phase: .start
                    )
                )
            )
        )
        return try await collectRemoteCompactionV2Output(from: stream).summaryText
    }

    let sink = SessionRetrySink(session: sess, turnContext: stepContext.turn)
    while true {
        do {
            return try await streamOnce(stepContext)
        } catch {
            let err = (error as? CodexErr) ?? CodexErr.fatal(String(describing: error))
            if let fallback = sess.fallbackStepContext,
               fallback.turn.model != stepContext.turn.model,
               shouldRetryWithCurrentModel(err) {
                do {
                    let summary = try await streamOnce(fallback)
                    sess.lastCompactModelFallback = recordModelFallback(
                        previousModel: stepContext.turn.model,
                        currentModel: fallback.turn.model,
                        fallbackError: nil
                    )
                    return summary
                } catch {
                    sess.lastCompactModelFallback = recordModelFallback(
                        previousModel: stepContext.turn.model,
                        currentModel: fallback.turn.model,
                        fallbackError: (error as? CodexErr) ?? err
                    )
                    throw err
                }
            }
            try await handleResponseStreamError(
                retryState: &retryState,
                maxRetries: maxRetries,
                err: err,
                trySwitchFallback: { clientSession.trySwitchFallbackTransport() },
                sink: sink,
                request: .remoteCompactionV2
            )
        }
    }
}

func runSamplingRequest(
    sess: Session,
    stepContext: StepContext,
    clientSession: inout ModelClientSession?,
    input: [ResponseItem],
    cancellationToken: CancellationToken
) async throws -> SamplingRequestResult {
    if cancellationToken.isCancelled {
        throw CodexErr(details: .turnAborted)
    }
    if let override = sess.runSamplingOverride {
        return try await override(input, stepContext)
    }

    if let prepare = sess.prepareSamplingPrompt {
        await prepare()
    }
    let baseInstructions = sess.getPromptBaseInstructions()
    var retryState = ResponsesStreamRetryState()
    let maxRetries = clientSession?.client.providerInfo.streamMaxRetries() ?? 0
    var initialInput: [ResponseItem]? = input
    var originalInput: [ResponseItem]?
    let sink = SessionRetrySink(session: sess, turnContext: stepContext.turn)

    while true {
        if cancellationToken.isCancelled {
            throw CodexErr(details: .turnAborted)
        }
        var promptInput: [ResponseItem]
        if let input = initialInput {
            initialInput = nil
            promptInput = input
        } else {
            promptInput = sess.cloneHistory().forPrompt()
        }
        sess.services.executedToolCalls.attachToPrompt(&promptInput)
        let prompt = buildPrompt(
            input: promptInput,
            stepContext: stepContext,
            baseInstructions: baseInstructions,
            sess: sess
        )
        if Guardian.isBasicSessionSource(stepContext.turn.sessionSource) {
            try GuardianRequestBudget.checkPrompt(
                session: sess,
                prompt: prompt,
                config: stepContext.turn.config,
                model: stepContext.turn.modelInfoValue()
            )
        }
        do {
            return try await tryRunSamplingRequest(
                sess: sess,
                stepContext: stepContext,
                clientSession: &clientSession,
                prompt: prompt,
                cancellationToken: cancellationToken.childToken()
            )
        } catch {
            let err = (error as? CodexErr) ?? CodexErr.fatal(String(describing: error))
            switch err.details {
            case .contextWindowExceeded:
                sess.setTotalTokensFull(stepContext.turn)
                throw err
            case .usageLimitReached(let limit):
                if let snapshot = limit.rateLimits {
                    sess.updateRateLimits(stepContext.turn, snapshot)
                }
                throw err
            default:
                break
            }
            if originalInput == nil {
                originalInput = prompt.input
            }
            try await handleResponseStreamError(
                retryState: &retryState,
                maxRetries: maxRetries,
                err: err,
                trySwitchFallback: { clientSession?.trySwitchFallbackTransport() ?? false },
                sink: sink,
                request: .sampling
            )
        }
    }
}

struct OutputItemResult: Sendable {
    var lastAgentMessage: String?
    var needsFollowUp: Bool
    var toolFuture: Task<ResponseItem, Error>?

    init(
        lastAgentMessage: String? = nil,
        needsFollowUp: Bool = false,
        toolFuture: Task<ResponseItem, Error>? = nil
    ) {
        self.lastAgentMessage = lastAgentMessage
        self.needsFollowUp = needsFollowUp
        self.toolFuture = toolFuture
    }
}

func handleOutputItemDone(
    sess: Session,
    stepContext: StepContext,
    item: ResponseItem,
    cancellationToken: CancellationToken,
    itemAlreadyStarted: Bool = false
) async throws -> OutputItemResult {
    do {
        if let call = try ToolRouter.buildToolCall(item) {
            sess.inputQueue.acceptMailboxDeliveryForCurrentTurn(
                sess.activeTurn,
                subId: stepContext.turn.subId
            )
            sess.recordConversationItems(stepContext.turn, items: [item])
            let runtime = ToolCallRuntime(session: sess, stepContext: stepContext)
            let child = cancellationToken.childToken()
            let future = Task {
                let output = try await runtime.handleToolCall(call, cancellationToken: child)
                sess.recordConversationItems(stepContext.turn, items: [output])
                return output
            }
            return OutputItemResult(needsFollowUp: true, toolFuture: future)
        }
    } catch let error as FunctionCallError {
        switch error {
        case .fatal(let message):
            throw CodexErr.fatal(message)
        case .respondToModel(let message):
            sess.services.executedToolCalls.observeNonDispatchedCall(item)
            sess.recordConversationItems(stepContext.turn, items: [item])
            let output = ResponseItem.functionCallOutput(
                id: nil,
                callId: "",
                name: nil,
                namespace: nil,
                output: FunctionCallOutputPayload(body: .text(message)),
                internalChatMessageMetadataPassthrough: nil
            )
            sess.recordConversationItems(stepContext.turn, items: [output])
            return OutputItemResult(needsFollowUp: true)
        }
    }

    sess.services.executedToolCalls.observeNonDispatchedCall(item)
    emitCompletedTurnItem(
        sess: sess,
        turnContext: stepContext.turn,
        item: item,
        itemAlreadyStarted: itemAlreadyStarted
    )
    sess.recordConversationItems(stepContext.turn, items: [item])
    return OutputItemResult(lastAgentMessage: lastAssistantMessageFromItem(item))
}

func emitCompletedTurnItem(
    sess: Session,
    turnContext: TurnContext,
    item: ResponseItem,
    itemAlreadyStarted: Bool
) {
    guard let turnItem = parseTurnItem(item) else { return }
    if stepContextIsPlanModeEmptyAssistant(turnContext: turnContext, item: item, turnItem: turnItem) {
        return
    }
    if !itemAlreadyStarted {
        sess.emitTurnItemStarted(turnContext, turnItem)
    }
    sess.emitTurnItemCompleted(turnContext, turnItem)
}

func stepContextIsPlanModeEmptyAssistant(
    turnContext: TurnContext,
    item: ResponseItem,
    turnItem: TurnItem
) -> Bool {
    guard turnContext.mode() == .plan, case .agentMessage = turnItem else { return false }
    let text = lastAssistantMessageFromItem(item) ?? ""
    return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
}

func lastAssistantMessageFromItem(_ item: ResponseItem) -> String? {
    getLastAssistantMessage(from: [item])
}

func tryRunSamplingRequest(
    sess: Session,
    stepContext: StepContext,
    clientSession: inout ModelClientSession?,
    prompt: Prompt,
    cancellationToken: CancellationToken
) async throws -> SamplingRequestResult {
    if cancellationToken.isCancelled {
        throw CodexErr(details: .turnAborted)
    }
    let stream: CodexCore.ResponseStream
    if let override = sess.runSamplingStreamOverride {
        sess.samplingClientSession = clientSession
        sess.samplingStepContext = stepContext
        stream = try await override(prompt)
    } else if let clientSession {
        stream = try await clientSession.stream(
            prompt: prompt,
            modelInfo: stepContext.turn.modelInfoValue(),
            responsesMetadata: sess.responsesMetadata(stepContext, requestKind: .turn)
        )
    } else {
        return SamplingRequestResult(
            needsFollowUp: false,
            lastAgentMessage: getLastAssistantMessageFromTurn(prompt.input)
        )
    }

    var needsFollowUp = false
    var lastAgentMessage: String?
    var inFlight: [Task<ResponseItem, Error>] = []
    let planMode = stepContext.turn.mode() == .plan
    var parsers = AssistantMessageStreamParsers(planMode: planMode)
    var planModeState = planMode ? PlanModeStreamState(turnId: stepContext.turn.subId) : nil
    var activeStreamItemId: String?
    var activeToolCallId: String?
    var startedItemIds = Set<String>()
    var activeDiffConsumer: (callId: String, consumer: any ToolArgumentDiffConsumer)?

    for await event in stream.events {
        if cancellationToken.isCancelled || stream.consumerDropped.isCancelled {
            throw CodexErr(details: .turnAborted)
        }
        let value: ResponseEvent
        switch event {
        case .success(let event):
            value = event
        case .failure(let error):
            throw error
        }
        switch value {
        case .created(responseId: let responseId):
            if let responseId {
                sess.lastResponseId = responseId
            }
        case .safetyBuffering(let buffering):
            sess.lastSafetyBuffering = buffering
            sess.sendEvent(
                stepContext.turn,
                .safetyBuffering(
                    SafetyBufferingEvent(
                        model: stepContext.turn.model,
                        useCases: buffering.useCases,
                        reasons: buffering.reasons,
                        showBufferingUi: buffering.showBufferingUi,
                        fasterModel: buffering.fasterModel
                    )
                )
            )
        case .serverReasoningIncluded(let included):
            sess.setServerReasoningIncluded(included)
        case .outputItemAdded(let item):
            if let id = item.id()?.asStr {
                activeStreamItemId = id
            }
            if let callId = toolCallId(from: item) {
                activeToolCallId = callId
            }
            if let attached = createToolArgumentDiffConsumer(for: item) {
                activeDiffConsumer = attached
            } else if toolCallId(from: item) != nil {
                activeDiffConsumer = nil
            }
            if let turnItem = parseTurnItem(item) {
                sess.emitTurnItemStarted(stepContext.turn, turnItem)
                startedItemIds.insert(turnItem.id)
            }
            if isAssistantMessageItem(item), let text = lastAssistantMessageFromItem(item) {
                let itemId = activeStreamItemId ?? "assistant"
                let parsed = parsers.seedItemText(itemId, text)
                emitStreamedAssistantTextDelta(
                    sess: sess,
                    turnContext: stepContext.turn,
                    planModeState: &planModeState,
                    itemId: itemId,
                    parsed: parsed
                )
            }
        case .outputTextDelta(let delta):
            let itemId = activeStreamItemId ?? "assistant"
            let parsed = parsers.parseDelta(itemId, delta)
            emitStreamedAssistantTextDelta(
                sess: sess,
                turnContext: stepContext.turn,
                planModeState: &planModeState,
                itemId: itemId,
                parsed: parsed
            )
        case .toolCallInputDelta(itemId: _, callId: let callId, delta: let delta):
            let resolvedCallId = callId ?? activeToolCallId
            if let resolvedCallId {
                sess.lastToolCallInputDeltas.append((callId: resolvedCallId, delta: delta))
                if let active = activeDiffConsumer,
                   callId == nil || callId == active.callId,
                   let event = active.consumer.consumeDiff(
                    turn: stepContext.turn,
                    callId: resolvedCallId,
                    delta: delta
                   ) {
                    sess.sendEvent(stepContext.turn, event)
                }
            }
        case .outputItemDone(let item):
            if let finished = try activeDiffConsumer?.consumer.finish() {
                sess.sendEvent(stepContext.turn, finished)
            }
            activeDiffConsumer = nil
            if let id = item.id()?.asStr {
                let parsed = parsers.finishItem(id)
                emitStreamedAssistantTextDelta(
                    sess: sess,
                    turnContext: stepContext.turn,
                    planModeState: &planModeState,
                    itemId: id,
                    parsed: parsed
                )
            }
            if var state = planModeState {
                maybeCompletePlanItemFromMessage(
                    sess: sess,
                    turnContext: stepContext.turn,
                    state: &state,
                    item: item
                )
                planModeState = state
            }
            let alreadyStarted = parseTurnItem(item).map { startedItemIds.contains($0.id) } ?? false
            let output = try await handleOutputItemDone(
                sess: sess,
                stepContext: stepContext,
                item: item,
                cancellationToken: cancellationToken,
                itemAlreadyStarted: alreadyStarted
            )
            activeToolCallId = nil
            if let future = output.toolFuture {
                inFlight.append(future)
            }
            if let message = output.lastAgentMessage {
                lastAgentMessage = message
            }
            needsFollowUp = needsFollowUp || output.needsFollowUp
            if shouldPreemptForMailbox(sess: sess, turnContext: stepContext.turn, item: item) {
                for task in inFlight {
                    _ = try await task.value
                }
                return SamplingRequestResult(needsFollowUp: true, lastAgentMessage: lastAgentMessage)
            }
        case .completed(responseId: let responseId, tokenUsage: let tokenUsage, usageMetadata: _, endTurn: let endTurn):
            for (itemId, parsed) in parsers.drainFinished() {
                emitStreamedAssistantTextDelta(
                    sess: sess,
                    turnContext: stepContext.turn,
                    planModeState: &planModeState,
                    itemId: itemId,
                    parsed: parsed
                )
            }
            sess.recordCompletedUsage(stepContext.turn, responseId: responseId, usage: tokenUsage)
            if endTurn == false {
                needsFollowUp = true
            }
            for task in inFlight {
                _ = try await task.value
            }
            return SamplingRequestResult(
                needsFollowUp: needsFollowUp,
                lastAgentMessage: lastAgentMessage
            )
        case .rateLimits(let snapshot):
            sess.updateRateLimits(stepContext.turn, snapshot)
        case .reasoningContentDelta(delta: let delta, contentIndex: let contentIndex):
            sess.sendEvent(
                stepContext.turn,
                .reasoningContentDelta(
                    ReasoningContentDeltaEvent(
                        threadId: sess.threadId.description,
                        turnId: stepContext.turn.subId,
                        itemId: activeStreamItemId ?? "reasoning",
                        delta: delta,
                        summaryIndex: contentIndex
                    )
                )
            )
        case .reasoningSummaryDelta(delta: let delta, summaryIndex: let summaryIndex):
            sess.sendEvent(
                stepContext.turn,
                .reasoningContentDelta(
                    ReasoningContentDeltaEvent(
                        threadId: sess.threadId.description,
                        turnId: stepContext.turn.subId,
                        itemId: activeStreamItemId ?? "reasoning",
                        delta: delta,
                        summaryIndex: summaryIndex
                    )
                )
            )
        case .reasoningSummaryPartAdded(summaryIndex: let summaryIndex):
            sess.lastReasoningSummaryPartIndex = summaryIndex
            sess.sendEvent(
                stepContext.turn,
                .agentReasoningSectionBreak(
                    AgentReasoningSectionBreakEvent(
                        itemId: activeStreamItemId ?? "reasoning",
                        summaryIndex: summaryIndex
                    )
                )
            )
        case .reasoningSummaryDone(itemId: _, text: let text, summaryIndex: _):
            sess.sendEvent(
                stepContext.turn,
                .agentReasoning(AgentReasoningEvent(text: text))
            )
        default:
            break
        }
    }

    if cancellationToken.isCancelled {
        throw CodexErr(details: .turnAborted)
    }
    throw CodexErr.stream("stream closed before response.completed")
}

func makeResponseStream(_ events: [CodexResult<ResponseEvent>]) -> CodexCore.ResponseStream {
    CodexCore.ResponseStream(events: AsyncStream { continuation in
        for event in events {
            continuation.yield(event)
        }
        continuation.finish()
    })
}

struct SessionRetrySink: ResponsesStreamRetrySink {
    let session: Session
    let turnContext: TurnContext

    var unboundedConnectionRetries: Bool {
        session.features.enabled(.unboundedConnectionRetries)
            || turnContext.config.features.enabled(.unboundedConnectionRetries)
    }

    var sessionSourceIsInternal: Bool {
        if case .internal = turnContext.sessionSource { return true }
        return false
    }

    var isAmazonBedrock: Bool { false }
    var responsesWebsocketEnabled: Bool { false }
    var turnId: String { turnContext.subId }

    func notifyStreamError(_ message: String, error: CodexErr) async {
        session.sendEvent(turnContext, .error(ErrorEvent(message: "\(message): \(error)")))
    }

    func sendWarning(_ message: String) async {
        session.sendEvent(turnContext, .error(ErrorEvent(message: message)))
    }

    func storeExhaustedRetry(_ retry: ExhaustedResponseRetry) async {
        _ = retry
    }
}

func inspectPendingInput(_ inputItem: SessionTurnInput, projectRoot: URL) async -> HookRuntimeOutcome {
    switch inputItem {
    case .userInput(let content, _, _):
        let prompt = content.compactMap { item -> String? in
            if case .text(let text, _) = item { return text }
            return nil
        }.joined(separator: "\n")
        return await HookRuntime.userPromptSubmit(prompt, projectRoot: projectRoot)
    default:
        return .proceed
    }
}

func recordPendingInput(
    sess: Session,
    turnContext: TurnContext,
    inputItem: SessionTurnInput,
    additionalContexts: [String],
    persistContext: PersistContext
) {
    _ = persistContext
    switch inputItem {
    case .userInput(let content, _, _):
        if !content.isEmpty {
            sess.recordConversationItems(turnContext, items: [responseItemFromUserInput(content)])
        }
    case .responseItem(let item), .functionCallOutput(let item):
        sess.recordConversationItems(turnContext, items: [item])
    case .interAgentCommunication:
        break
    }
    recordAdditionalContexts(sess: sess, turnContext: turnContext, contexts: additionalContexts)
}

func recordAdditionalContexts(
    sess: Session,
    turnContext: TurnContext,
    contexts: [String]
) {
    guard !contexts.isEmpty else { return }
    let items = contexts.map { text in
        ResponseItem.message(
            id: nil,
            role: "user",
            content: [.inputText(text: text)],
            phase: nil,
            internalChatMessageMetadataPassthrough: nil
        )
    }
    sess.recordConversationItems(turnContext, items: items)
}

func drainAsyncHookResults(sess: Session, turnContext: TurnContext, beforeUserPrompt: Bool) {
    _ = beforeUserPrompt
    recordAdditionalContexts(
        sess: sess,
        turnContext: turnContext,
        contexts: sess.takePendingHookContexts()
    )
}

func runPendingSessionStartHooks(sess: Session, turnContext: TurnContext) async -> Bool {
    if sess.sessionStartHooksConsumed { return false }
    sess.sessionStartHooksConsumed = true
    let projectRoot = URL(fileURLWithPath: turnContext.cwd, isDirectory: true)
    if let reason = await HookRuntime.sessionStartDenial(projectRoot: projectRoot) {
        sess.sendEvent(turnContext, .error(ErrorEvent(message: reason)))
        return true
    }
    return false
}

func checkPendingGuardianInput(sess: Session, turnContext: TurnContext) throws {
    try GuardianInputBudget.checkPending(session: sess, turn: turnContext)
}

func finalizeGuardianInput(
    sess: Session,
    stepContext: StepContext,
    input: inout [SessionTurnInput]
) throws {
    try GuardianInputBudget.finalize(session: sess, step: stepContext, input: &input)
}

struct AssistantMessageStreamParsers {
    var planMode: Bool
    var parsersByItem: [String: AssistantTextStreamParser] = [:]

    init(planMode: Bool) {
        self.planMode = planMode
    }

    mutating func parser(for itemId: String) -> AssistantTextStreamParser {
        if let existing = parsersByItem[itemId] {
            return existing
        }
        let created = AssistantTextStreamParser(planMode: planMode)
        parsersByItem[itemId] = created
        return created
    }

    mutating func seedItemText(_ itemId: String, _ text: String) -> AssistantTextChunk {
        if text.isEmpty { return AssistantTextChunk() }
        return parser(for: itemId).pushStr(text)
    }

    mutating func parseDelta(_ itemId: String, _ delta: String) -> AssistantTextChunk {
        parser(for: itemId).pushStr(delta)
    }

    mutating func finishItem(_ itemId: String) -> AssistantTextChunk {
        guard let parser = parsersByItem.removeValue(forKey: itemId) else {
            return AssistantTextChunk()
        }
        return parser.finish()
    }

    mutating func drainFinished() -> [(String, AssistantTextChunk)] {
        let remaining = parsersByItem
        parsersByItem = [:]
        return remaining.map { ($0.key, $0.value.finish()) }
    }
}

struct PlanModeStreamState {
    var planItemId: String
    var planStarted = false
    var planCompleted = false
    var planText = ""

    init(turnId: String) {
        planItemId = "\(turnId)-plan"
    }
}

func isAssistantMessageItem(_ item: ResponseItem) -> Bool {
    if case .message(_, let role, _, _, _) = item {
        return role == "assistant"
    }
    return false
}

func emitStreamedAssistantTextDelta(
    sess: Session,
    turnContext: TurnContext,
    planModeState: inout PlanModeStreamState?,
    itemId: String,
    parsed: AssistantTextChunk
) {
    if parsed.isEmpty { return }
    if var state = planModeState {
        handlePlanSegments(
            sess: sess,
            turnContext: turnContext,
            state: &state,
            itemId: itemId,
            segments: parsed.planSegments
        )
        planModeState = state
        return
    }
    if parsed.visibleText.isEmpty { return }
    sess.sendEvent(
        turnContext,
        .agentMessageContentDelta(
            AgentMessageContentDeltaEvent(
                threadId: sess.threadId.description,
                turnId: turnContext.subId,
                itemId: itemId,
                delta: parsed.visibleText
            )
        )
    )
}

func handlePlanSegments(
    sess: Session,
    turnContext: TurnContext,
    state: inout PlanModeStreamState,
    itemId: String,
    segments: [ProposedPlanSegment]
) {
    for segment in segments {
        switch segment {
        case .normal(let delta):
            if delta.isEmpty { continue }
            sess.sendEvent(
                turnContext,
                .agentMessageContentDelta(
                    AgentMessageContentDeltaEvent(
                        threadId: sess.threadId.description,
                        turnId: turnContext.subId,
                        itemId: itemId,
                        delta: delta
                    )
                )
            )
        case .proposedPlanStart:
            startPlanItem(sess: sess, turnContext: turnContext, state: &state)
        case .proposedPlanDelta(let delta):
            startPlanItem(sess: sess, turnContext: turnContext, state: &state)
            if !delta.isEmpty, !state.planCompleted {
                state.planText += delta
                sess.sendEvent(
                    turnContext,
                    .agentMessageContentDelta(
                        AgentMessageContentDeltaEvent(
                            threadId: sess.threadId.description,
                            turnId: turnContext.subId,
                            itemId: state.planItemId,
                            delta: delta
                        )
                    )
                )
            }
        case .proposedPlanEnd:
            break
        }
    }
}

func startPlanItem(sess: Session, turnContext: TurnContext, state: inout PlanModeStreamState) {
    guard !state.planStarted, !state.planCompleted else { return }
    state.planStarted = true
    sess.sendEvent(
        turnContext,
        .itemStarted(
            ItemStartedEvent(
                threadId: sess.threadId,
                turnId: turnContext.subId,
                item: .plan(PlanItem(id: state.planItemId, text: "")),
                startedAtMs: 0
            )
        )
    )
}

func maybeCompletePlanItemFromMessage(
    sess: Session,
    turnContext: TurnContext,
    state: inout PlanModeStreamState,
    item: ResponseItem
) {
    guard isAssistantMessageItem(item) else { return }
    let text = lastAssistantMessageFromItem(item) ?? ""
    guard let planText = extractProposedPlanText(text) else { return }
    if !state.planStarted {
        startPlanItem(sess: sess, turnContext: turnContext, state: &state)
    }
    guard !state.planCompleted else { return }
    state.planCompleted = true
    sess.sendEvent(
        turnContext,
        .itemCompleted(
            ItemCompletedEvent(
                threadId: sess.threadId,
                turnId: turnContext.subId,
                item: .plan(PlanItem(id: state.planItemId, text: planText)),
                startedAtMs: nil,
                completedAtMs: 0
            )
        )
    )
}

func toolCallId(from item: ResponseItem) -> String? {
    switch item {
    case .functionCall(_, _, _, _, _, let callId, _),
         .customToolCall(_, _, let callId, _, _, _, _):
        return callId
    case .toolSearchCall(_, let callId, _, _, _, _),
         .localShellCall(_, let callId, _, _, _):
        return callId
    default:
        return nil
    }
}

func shouldPreemptForMailbox(sess: Session, turnContext: TurnContext, item: ResponseItem) -> Bool {
    if turnContext.config.features.enabled(.deferMailboxPreemption)
        || sess.features.enabled(.deferMailboxPreemption) {
        return false
    }
    guard sess.inputQueue.hasPendingMailboxItems() else { return false }
    switch item {
    case .message(_, let role, _, let phase, _):
        return role == "assistant" && phase == .commentary
    case .reasoning:
        return true
    default:
        return false
    }
}

func mcpServerName(from path: String) -> String? {
    guard path.hasPrefix("mcp://") else { return nil }
    let rest = String(path.dropFirst("mcp://".count))
    guard !rest.isEmpty else { return nil }
    return rest.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init)
}

func mcpServerNamesMentioned(in text: String) -> Set<String> {
    var names = Set<String>()
    var search = text[...]
    while let range = search.range(of: "mcp://") {
        let after = search[range.upperBound...]
        let server = after.prefix(while: { $0 != "/" && !$0.isWhitespace })
        if !server.isEmpty {
            names.insert(String(server))
        }
        search = after
    }
    return names
}

func uniquedPreservingOrder(_ values: [String]) -> [String] {
    var seen = Set<String>()
    return values.filter { seen.insert($0).inserted }
}

func isToolCollision(_ error: CodexErr) -> Bool {
    if case .toolCollision = error.details { return true }
    return false
}
