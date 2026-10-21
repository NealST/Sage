//
//  TaskHarness.swift
//  Sage
//
//  Sage addition (no codex counterpart).
//
//  One persistent harness Session (root SageThread) per active task — the
//  M3 single-thread topology. Plan, execute, review, and rework turns all
//  submit onto this session, so history continuity is the session itself.
//  Session creation and destruction happen only here; the one-time
//  events→history reverse mapping runs at creation (new task / recovery),
//  never per turn. Also owns the per-task thread registry, the Responses
//  client lease pool, and the rollout file identity.
//

import SageAPI
import SageCore
import SageProtocol
import Foundation

@MainActor
final class TaskHarness {
    let taskID: UUID?
    let session: Session
    let threadId: ThreadId
    let threadManager: ThreadManager
    /// Start source queued into the session at creation (`.clear` on a fresh
    /// task, `.fork` after a peel, `.resume`/`.startup` on recovery).
    let startSource: SessionStartSource
    /// ID of the userInput event already recorded in session history. A
    /// later turn resubmits it only when a NEWER user input exists.
    var recordedUserInputEventID: UUID?
    /// Base URL whose `/responses` endpoint 404'd. Other providers stay on
    /// the Responses transport.
    private(set) var responsesTransportUnavailableURL: String?
    private(set) var isShutDown = false
    /// Execute turns prepared on this harness (first turn reports
    /// `startSource` to hooks, later ones report `.resume`).
    private(set) var executeTurnsStarted = 0

    private let state: AgentSessionState
    private let modelGateway: AgentModelGateway
    private weak var task: RegularTask?
    /// Responses clients keyed by "baseURL\napiKey", each minted with the
    /// harness thread id so phase roles and Execute share wire identity.
    private var leases: [String: ExecuteHarnessAttach.ResponsesClientLease] = [:]
    private let resumedRolloutPath: String?

    init(
        taskID: UUID?,
        task: RegularTask,
        state: AgentSessionState,
        modelGateway: AgentModelGateway,
        remembered: (threadId: ThreadId, rolloutPath: String?)?
    ) {
        self.taskID = taskID
        self.task = task
        self.state = state
        self.modelGateway = modelGateway
        self.resumedRolloutPath = remembered?.rolloutPath
        let settings = modelGateway.settings.snapshot(for: .execute)
        // The one events→history reverse mapping: everything up to and
        // including the last userInput becomes session history. Turns after
        // this append to the session instead of rebuilding it.
        let events = state.events
        let history: [ResponseItem]
        if let lastUserIndex = events.lastIndex(where: { $0.kind == .userInput }) {
            history = events[...lastUserIndex].flatMap(ExecuteHarnessAttach.responseItems(from:))
        } else {
            history = events.flatMap(ExecuteHarnessAttach.responseItems(from:))
        }
        recordedUserInputEventID = events.last(where: { $0.kind == .userInput })?.id
        let threadId = remembered?.threadId ?? ThreadId()
        let startSource = ExecuteHarnessAttach.attachStartSource(
            pending: state.takePendingSessionStartSource(),
            historyEmpty: history.isEmpty
        )
        let session = ExecuteHarnessAttach.makeSession(
            history: history,
            threadId: threadId,
            startSource: startSource,
            discardEvents: true
        )
        self.session = session
        self.threadId = threadId
        self.startSource = startSource
        threadManager = ThreadManager()
        installExecuteServices()
        threadManager.setTurnToolRunner(ExecuteChildToolRunner(task: task))
        try? threadManager.adoptRootThread(
            threadId: threadId,
            model: settings.model,
            cwd: cwd,
            history: session.cloneHistory().forPrompt()
        )
        session.services.threadManager = threadManager
        session.services.localAgentControl = threadManager.agentControl(
            sessionId: SessionId(threadId)
        )
        if let path = remembered?.rolloutPath {
            session.restoreVerifiedAnswers(
                fromRolloutPath: path,
                truncationPolicy: TruncationPolicy(
                    TurnContext(model: settings.model).modelInfoValue().truncationPolicy
                )
            )
            session.resumeRolloutPersistence(path: path)
        } else {
            session.enableRolloutPersistence()
        }
        session.ensureSubmissionLoop()
    }

    private var cwd: String { state.projectCWD }

    /// `nil` until the lazy rollout recorder writes its first item.
    var rolloutPath: String? {
        session.persistedRolloutPath() ?? resumedRolloutPath
    }

    /// One Responses client per (baseURL, apiKey). Same credentials reuse the
    /// client; every client carries this harness's thread id.
    func leaseClient(_ settings: ModelSettingsSnapshot) -> ExecuteHarnessAttach.ResponsesClientLease? {
        let key = settings.baseURL + "\n" + settings.apiKey
        if let existing = leases[key] { return existing }
        let lease = ExecuteHarnessAttach.leaseResponsesClient(
            existing: nil,
            baseURL: settings.baseURL,
            apiKey: settings.apiKey,
            threadId: threadId
        )
        guard let lease else { return nil }
        leases[key] = lease
        return lease
    }

    func responsesTransportUnavailable(_ settings: ModelSettingsSnapshot) -> Bool {
        !settings.baseURL.isEmpty && responsesTransportUnavailableURL == settings.baseURL
    }

    func markResponsesTransportUnavailable(_ settings: ModelSettingsSnapshot) {
        guard !settings.baseURL.isEmpty else { return }
        responsesTransportUnavailableURL = settings.baseURL
    }

    /// Refresh turn-scoped session state before an execute turn: the Execute
    /// model client (hookActivatedSkills / mcpVisibleTools snapshots go stale
    /// when taken once at attach), the root thread's mirrored history, and
    /// the child tool list.
    func prepareExecuteTurn() {
        guard !isShutDown else { return }
        let settings = modelGateway.settings.snapshot(for: .execute)
        let lease = leaseClient(settings)
        session.services.modelClient = responsesTransportUnavailable(settings) ? nil : lease?.client
        if let client = session.services.modelClient {
            threadManager.attachModelClient(client, model: settings.model)
        }
        session.services.hookActivatedSkills = task?.hookActivatedSkills?() ?? []
        session.services.mcpVisibleTools = task?.mcpVisibleCatalog?() ?? []
        try? threadManager.adoptRootThread(
            threadId: threadId,
            model: settings.model,
            cwd: cwd,
            history: session.cloneHistory().forPrompt()
        )
        refreshChildModelTools()
        executeTurnsStarted += 1
    }

    /// Explore children sample through the harness model client. Attach one
    /// even when no execute turn has run yet (skill-fork explore can run
    /// mid-answer-turn, before `prepareExecuteTurn` ever fires).
    func prepareExploreSpawn() {
        guard !isShutDown, session.services.modelClient == nil else { return }
        let settings = modelGateway.settings.snapshot(for: .execute)
        guard !responsesTransportUnavailable(settings), let lease = leaseClient(settings) else {
            return
        }
        session.services.modelClient = lease.client
        threadManager.attachModelClient(lease.client, model: settings.model)
    }

    /// Releases the submission-loop strong cycle. Safe to call with a turn
    /// in flight: the loop aborts it before exiting.
    func shutdown() async {
        guard !isShutDown else { return }
        isShutDown = true
        await session.shutdownAndWait()
    }

    private func installExecuteServices() {
        session.services.parallelAdmission = state.parallelAdmission
        session.services.approvalStore = state.sessionAllowlist.approvalStore
        if case .project(let root) = state.pathGuardPolicy {
            session.services.hookProjectRoot = root
        }
        session.services.mcpVisibleTools = task?.mcpVisibleCatalog?() ?? []
        session.services.ensureMcpConnected = { [weak self] in
            await self?.task?.ensureMCPConnected?()
        }
        session.services.reconnectMcp = { [weak self] in
            await self?.task?.reconnectMCP?()
        }
        session.services.disconnectMcp = { [weak self] names in
            await self?.task?.disconnectMCP?(names)
        }
        session.services.mcpToolTransport = { [weak self] request in
            guard let task = await self?.task else {
                throw McpToolCallFailure("MCP transport is gone")
            }
            let invoke = await task.invokeHarnessTool
            guard let invoke else {
                throw McpToolCallFailure("MCP transport is not attached")
            }
            let qualified = "mcp__\(request.serverName)__\(request.toolName)"
            let text = try await invoke(
                ToolCallProposal(
                    id: UUID().uuidString,
                    name: qualified,
                    argumentsJSON: request.argumentsJSON
                )
            )
            return callToolResult(fromTransportText: text, isError: text.hasPrefix("ERROR:"))
        }
        session.services.sageToolSpecs = ExecuteHarnessAttach.sageToolSpecs(
            modelGateway.availableToolDefinitions()
        )
        refreshChildModelTools()
        session.prepareSamplingPrompt = { [weak self] in
            guard let self else { return }
            let includeTools = self.task?.harnessIncludeTools ?? true
            let prefix = await self.modelGateway.samplingPrefix(includeTools: includeTools)
            self.session.state.sessionConfiguration.baseInstructions = prefix.system
            self.session.services.sageToolSpecs = includeTools
                ? ExecuteHarnessAttach.sageToolSpecs(prefix.tools)
                : []
            self.refreshChildModelTools()
        }
        session.services.onSageToolCall = { [weak self] name, callId, arguments in
            await self?.task?.dispatchSageTool(
                name: name,
                callId: callId,
                argumentsJSON: arguments
            )
        }
        session.runSamplingStreamOverride = { [weak self] prompt in
            guard let self, let task = self.task else {
                throw SageErr.fatal("execute harness sampler is gone")
            }
            if let resume = task.resumeToolTurn {
                task.resumeToolTurn = nil
                return await task.streamAdmittedTools(
                    resume,
                    recordAssistant: false,
                    countRound: false,
                    replacePlan: false
                )
            }
            switch try await task.openModelSample(prompt) {
            case .buffered(let sample):
                return await task.streamBuffered(sample)
            case .live(let stream):
                return stream
            }
        }
    }

    /// Keeps ThreadManager's child-sampler tool list in sync with the live
    /// Sage tool specs, rendered in the wire format child samplers advertise.
    private func refreshChildModelTools() {
        threadManager.updateChildModelTools(
            session.services.sageToolSpecs.map { SageExecuteHandler(spec: $0).spec().toJSON() }
        )
    }
}
