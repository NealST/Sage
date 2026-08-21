//
//  AgentHostSurface.swift
//  Sage
//
//  SkillToolHost + SlashCommandHost implementation, kept off AgentRuntime.
//

import Foundation

@MainActor
final class AgentHostSurface: SkillToolHost, SlashCommandHost {
    private let state: AgentSessionState
    private let taskStore: AgentTaskStore
    private let skills: SkillSessionController
    private let settings: ModelSettings
    private let tools: ToolRegistry
    private weak var skillCatalog: SkillCatalog?
    private weak var mcpHub: CapabilityStore?
    var onSkillsCatalogChanged: (() async -> Void)?

    init(
        state: AgentSessionState,
        taskStore: AgentTaskStore,
        skills: SkillSessionController,
        settings: ModelSettings,
        tools: ToolRegistry,
        skillCatalog: SkillCatalog?,
        mcpHub: CapabilityStore?
    ) {
        self.state = state
        self.taskStore = taskStore
        self.skills = skills
        self.settings = settings
        self.tools = tools
        self.skillCatalog = skillCatalog
        self.mcpHub = mcpHub
    }

    func bindCatalog(_ catalog: SkillCatalog?) {
        skillCatalog = catalog
    }

    func bindMCPHub(_ hub: CapabilityStore?) {
        mcpHub = hub
    }

    // MARK: - SkillToolHost

    var activatedSkillNames: Set<String> { state.activatedSkillNames }
    var enabledSkills: [SkillRecord] { skillCatalog?.enabledSkills ?? [] }
    var catalogSkills: [SkillRecord] { skillCatalog?.skills ?? [] }
    var focusedProjectRoot: URL? { state.focusedProject?.rootURL }

    func broadcastSkillsCatalogChange() async {
        if let onSkillsCatalogChanged {
            await onSkillsCatalogChanged()
        } else {
            await skillCatalog?.reloadSkills(projectRoot: state.focusedProject?.rootURL)
        }
    }

    func activateSkill(named name: String) {
        state.activatedSkillNames.insert(name)
    }

    func runExploreSubagent(
        task: String,
        context: String?,
        instructions: String?,
        activatedSkillNames: Set<String>
    ) async throws -> String {
        try await ExploreSubagentRunner.runTask(
            ExploreSubagentRequest(
                task: task,
                context: context,
                instructions: instructions,
                settings: settings.snapshot(for: .execute),
                tools: tools,
                pathGuardPolicy: state.pathGuardPolicy,
                skillHost: self,
                activatedSkillNames: activatedSkillNames,
                enabledSkills: enabledSkills
            )
        )
    }

    func executeToolInvocation(name: String, argumentsJSON: String) async throws -> String {
        let activated = enabledSkills.filter { activatedSkillNames.contains($0.name) }
        let hookDecision = await PreToolUseHookEvaluator.shared.evaluate(
            toolName: name,
            argumentsJSON: argumentsJSON,
            projectRoot: state.focusedProject?.rootURL,
            activatedSkills: activated
        )
        switch hookDecision {
        case .allow:
            break

        case .ask(let reason):
            throw ToolError.operationFailed(
                "PreToolUse hook requires interactive approval: \(reason)"
            )

        case .deny(let reason):
            throw ToolError.operationFailed("Blocked by PreToolUse hook: \(reason)")
        }

        return try await taskStore.withActiveTaskContext {
            try await ToolInvocationDispatcher.execute(
                ToolInvocationRequest(
                    name: name,
                    argumentsJSON: argumentsJSON,
                    tools: tools,
                    mcp: mcpHub,
                    pathGuardPolicy: state.pathGuardPolicy,
                    activatedSkillNames: activatedSkillNames,
                    enabledSkills: enabledSkills,
                    skillHost: self,
                    workPlanKind: state.activeTask?.workPlan?.kind,
                    modelSettings: settings.snapshot(for: .execute)
                )
            )
        }
    }

    // MARK: - SlashCommandHost

    var isModelConfigured: Bool { settings.isConfigured }

    var usableTranscriptEventCount: Int {
        guard let task = state.activeTask else { return 0 }
        return task.events.filter { event in
            event.kind == .userInput || event.kind == .assistantResponse || event.kind == .toolResult
        }.count
    }

    func reportCommandFailure(_ message: String) {
        state.enterFailed(message: message)
    }

    func reportCommandThinking() {
        state.enterThinking()
    }

    func reportCommandCompleted(summary: String) {
        state.enterCompleted(summary: summary)
    }

    @discardableResult
    func ensureActiveTaskForCommand() async -> Bool {
        await taskStore.ensureActiveTask()
    }

    @discardableResult
    func appendProtectedUserInput(_ content: String) async -> Bool {
        let event = AgentEvent(kind: .userInput, content: content, protected: true)
        return await taskStore.commit(appendEvents: [event], deleteEventIDs: []) { _ in }
    }

    func scheduleExplicitRemember(userNote: String?) {
        guard let task = state.activeTask else { return }
        skills.scheduleExtraction(
            for: task,
            mode: .explicitRemember,
            userNote: userNote,
            presentImmediately: true
        )
    }

    func enabledSkill(named name: String) -> SkillRecord? {
        skillCatalog?.enabledSkills.first { $0.name == name }
    }

    func isSkillActivated(_ name: String) -> Bool {
        state.activatedSkillNames.contains(name)
    }

    func activateSkill(_ skill: SkillRecord) async -> Bool {
        let body = await SkillRegistry.shared.readBody(for: skill)
        guard !body.isEmpty else {
            reportCommandFailure("Skill '\(skill.name)' has no content.")
            return false
        }

        guard await taskStore.ensureActiveTask() else { return false }

        let content = await SkillToolExecutor.buildSkillContent(for: skill)
        let event = AgentEvent(
            kind: .userInput,
            content: "[Activated skill: \(skill.name)]\n\n\(content)",
            protected: true
        )

        activateSkill(named: skill.name)
        let didCommit = await taskStore.commit(appendEvents: [event], deleteEventIDs: []) { _ in }
        if !didCommit {
            state.activatedSkillNames.remove(skill.name)
            reportCommandFailure("Couldn’t activate skill '\(skill.name)'.")
        }
        return didCommit
    }

    func presentScheduleDraft(_ draft: ScheduleDraft) {
        skills.tips.enqueueSchedule(draft)
    }

    func presentScriptSchedule(prefill command: String?) {
        var draft = ScheduleScriptDraft.blank()
        if let command, !command.isEmpty {
            draft.command = command
        }
        skills.scriptScheduleDraft = draft
    }

    var scheduleScopeProjectID: UUID? { state.focusedProject?.id }
    var scheduleScopeLabel: String {
        state.focusedProject.map { "This Project · \($0.name)" } ?? "General"
    }
    var latestUserRequestText: String? {
        ScheduleRecord.latestUserRequest(in: state.activeTask?.events ?? [])
    }
    var scheduleOriginTaskID: UUID? { state.activeTaskID }

    /// Slash autocomplete: builtins + not-yet-activated skills.
    var availableSlashCommandDefinitions: [SlashCommandDefinition] {
        let skills = (skillCatalog?.enabledSkills ?? [])
            .filter { !state.activatedSkillNames.contains($0.name) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return SlashCommandRegistry.definitions(
            skills: skills.map { ($0.name, $0.description) }
        )
    }
}
