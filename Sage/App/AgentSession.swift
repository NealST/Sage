import Foundation

/// One agent workspace: General or a single Project.
/// Owns transcript/runtime/tips/draft for that window; tips live until this session ends.
@Observable
@MainActor
final class AgentSession: Identifiable {
    enum Kind: Hashable, Sendable {
        case general
        case project(UUID)

        var windowAutosaveName: String {
            switch self {
            case .general:
                return "SageAgentWindow.General"

            case .project(let id):
                return "SageAgentWindow.Project.\(id.uuidString)"
            }
        }
    }

    let kind: Kind
    var draft: String = "" {
        didSet { scheduleDraftPersist() }
    }
    var draftAttachments: [MessageAttachment] = [] {
        didSet { scheduleDraftPersist() }
    }
    var attachmentHint: String?
    private(set) var composerRevision: UInt = 0
    private var inFlightAttachmentIDs: Set<UUID> = []
    /// Unsent work survives quits and window closes — one JSON file per scope.
    private let draftStore: SessionDraftStore
    private var draftPersistTask: Task<Void, Never>?
    let agent: AgentRuntime
    /// Skills catalog for this window's focus. MCP tools come from AppState's shared hub.
    let skillCatalog: SkillCatalog
    /// Tip queues + save jobs (observation isolated from streaming runtime).
    let skills: SkillSessionController

    var id: Kind { kind }

    var projectID: UUID? {
        if case .project(let id) = kind { return id }
        return nil
    }

    var isGeneral: Bool {
        if case .general = kind { return true }
        return false
    }

    var windowAutosaveName: String { kind.windowAutosaveName }

    func resetComposer(discardManagedCopies: Bool = true) {
        if discardManagedCopies {
            MessageAttachment.deleteManagedCopies(
                draftAttachments.filter { !inFlightAttachmentIDs.contains($0.id) }
            )
        }
        draft = ""
        draftAttachments = []
        attachmentHint = nil
        composerRevision &+= 1
    }

    func beginAttachmentSubmission(_ attachments: [MessageAttachment]) -> UInt {
        inFlightAttachmentIDs.formUnion(attachments.map(\.id))
        return composerRevision
    }

    func finishAttachmentSubmission(
        _ attachments: [MessageAttachment],
        accepted: Bool,
        startingRevision: UInt
    ) {
        inFlightAttachmentIDs.subtract(attachments.map(\.id))
        if accepted {
            if composerRevision == startingRevision {
                resetComposer(discardManagedCopies: false)
            }
        } else if composerRevision != startingRevision {
            // The window/draft was cleared while submission was pending and no event owns the files.
            MessageAttachment.deleteManagedCopies(attachments)
        }
    }

    init(
        kind: Kind,
        settings: ModelSettings,
        taskRepository: any TaskRepository,
        mcpHub: CapabilityStore,
        skillStateStore: SkillStateStore
    ) {
        self.kind = kind
        self.draftStore = SessionDraftStore(scopeKey: kind.draftScopeKey)
        let skillCatalog = SkillCatalog(store: skillStateStore)
        let skills = SkillSessionController()
        self.skillCatalog = skillCatalog
        self.skills = skills
        let agent = AgentRuntime(
            settings: settings,
            tools: .makeDefault(),
            taskRepository: taskRepository,
            contextResolver: ContinuityTaskResolver(),
            skillCatalog: skillCatalog,
            mcpHub: mcpHub,
            skills: skills
        )
        self.agent = agent
        agent.state.turnInput.onChanged = { [weak self] in
            self?.scheduleDraftPersist()
        }
    }

    // MARK: - Draft persistence

    /// Submitted prompts, newest first — ⌘↑/⌘↓ recall in the composer.
    /// Seeded from the restored thread's user turns.
    var inputHistory: [String] = []
    private static let inputHistoryLimit = 60

    func recordSubmittedInput(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if inputHistory.first == trimmed { return }
        inputHistory.insert(trimmed, at: 0)
        if inputHistory.count > Self.inputHistoryLimit {
            inputHistory.removeLast()
        }
    }

    /// Debounced — composer keystrokes must not hit disk per character.
    func scheduleDraftPersist() {
        draftPersistTask?.cancel()
        draftPersistTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.flushDraftPersist()
        }
    }

    /// Immediate save — quit, window close, and other teardown paths.
    func flushDraftPersist() {
        draftPersistTask?.cancel()
        draftPersistTask = nil
        draftStore.save(currentDraftPayload())
    }

    func discardPersistedDraft() {
        draftPersistTask?.cancel()
        draftPersistTask = nil
        draftStore.discard()
    }

    /// Restores the persisted draft and queued turns after session bootstrap.
    /// An offer that was mid-dialog at quit folds into the queue (nothing is
    /// running at launch, so the interrupt dialog would have nothing to
    /// interrupt); an in-flight steer is dropped — its user event already
    /// persisted, and a stale pendingSteer would block draining forever.
    func restorePersistedDraft() async {
        seedInputHistoryFromEvents()
        guard let payload = draftStore.load() else { return }
        draft = payload.draft
        // Files may have moved or been deleted since the last run.
        draftAttachments = payload.draftAttachments.filter(\.isAvailable)

        let state = agent.state
        if let activeID = state.activeTaskID {
            if let input = payload.turnInputByTask[activeID.uuidString], !input.isEmpty {
                state.turnInput.apply(turnInputSnapshot(from: input))
            }
        }
        var parked: [UUID: TurnInputQueue.Snapshot] = [:]
        for (key, input) in payload.turnInputByTask {
            guard let taskID = UUID(uuidString: key),
                  taskID != state.activeTaskID,
                  !input.isEmpty else { continue }
            parked[taskID] = turnInputSnapshot(from: input)
        }
        state.parkedTurnInput = parked

        if state.turnInput.hasQueuedItems {
            await agent.drainQueuedTurns()
        }
    }

    private func currentDraftPayload() -> SessionDraftPayload {
        let state = agent.state
        var byTask: [String: PersistedTurnInput] = [:]
        for (taskID, snapshot) in state.parkedTurnInput where !snapshot.isEmpty {
            byTask[taskID.uuidString] = persistedTurnInput(from: snapshot)
        }
        if let activeID = state.activeTaskID {
            let snapshot = state.turnInput.snapshot
            if snapshot.isEmpty {
                // Clear stale persisted entries once the live queue drains.
                byTask.removeValue(forKey: activeID.uuidString)
            } else {
                byTask[activeID.uuidString] = persistedTurnInput(from: snapshot)
            }
        }
        return SessionDraftPayload(
            draft: draft,
            draftAttachments: draftAttachments,
            turnInputByTask: byTask
        )
    }

    /// An in-flight offer (interrupt dialog up at quit time) is queued behind
    /// the committed items.
    private func persistedTurnInput(from snapshot: TurnInputQueue.Snapshot) -> PersistedTurnInput {
        var turns = snapshot.items.map {
            PersistedQueuedTurn(text: $0.text, attachments: $0.attachments)
        }
        if let offer = snapshot.offer {
            turns.append(PersistedQueuedTurn(text: offer.text, attachments: offer.attachments))
        }
        return PersistedTurnInput(queuedItems: turns)
    }

    private func turnInputSnapshot(from input: PersistedTurnInput) -> TurnInputQueue.Snapshot {
        TurnInputQueue.Snapshot(
            offer: nil,
            items: input.queuedItems.map {
                QueuedUserTurn(text: $0.text, attachments: $0.attachments)
            },
            pendingSteer: nil
        )
    }

    private func seedInputHistoryFromEvents() {
        // Events are chronological; each insert-at-0 lands the newest entry first.
        for event in agent.state.events where event.kind == .userInput {
            recordSubmittedInput(event.content)
        }
    }
}

extension AgentSession.Kind {
    var draftScopeKey: String {
        switch self {
        case .general:
            return "general"

        case .project(let id):
            return "project-\(id.uuidString)"
        }
    }
}
