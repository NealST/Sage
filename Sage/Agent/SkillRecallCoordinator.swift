//
//  SkillRecallCoordinator.swift
//  Sage
//
//  Skill catalog appendix + explicit load_skill (slash / user choice).
//  Matching is left to the cloud model via the load_skill tool.
//

import Foundation

/// Per-window skill catalog cache and explicit activation.
@MainActor
final class SkillRecallCoordinator {
    private let state: AgentSessionState
    private let skills: SkillSessionController
    private let skillCatalog: () -> SkillCatalog?
    private let taskStore: AgentTaskStore
    private var skillHost: (() -> SkillToolHost?)?

    /// Cached skill appendix for the current user turn.
    private(set) var cachedResult: SkillCatalog.SkillAppendixResult?
    /// Query that produced `cachedResult` (for plan-step reuse).
    private(set) var cachedQuery: String?

    init(
        state: AgentSessionState,
        skills: SkillSessionController,
        skillCatalog: @escaping () -> SkillCatalog?,
        taskStore: AgentTaskStore
    ) {
        self.state = state
        self.skills = skills
        self.skillCatalog = skillCatalog
        self.taskStore = taskStore
    }

    func bind(skillHost: @escaping () -> SkillToolHost?) {
        self.skillHost = skillHost
    }

    func clearTurnCache() {
        cachedResult = nil
        cachedQuery = nil
    }

    func rememberCache(_ result: SkillCatalog.SkillAppendixResult, query: String) {
        cachedResult = result
        cachedQuery = query
    }

    /// Builds the Available Skills appendix. Never injects a skill body.
    @discardableResult
    func prepareSkillsForTurn(query: String) async -> Bool {
        guard let skillCatalog = skillCatalog() else { return true }
        let appendix = await skillCatalog.skillsPromptAppendix()
        rememberCache(appendix, query: query)
        return true
    }

    /// After the user picks a skill from a tip.
    func refreshCatalogWithoutRematch(query: String) async {
        guard let appendix = await skillCatalog()?.skillsPromptAppendix() else { return }
        rememberCache(appendix, query: query)
    }

    func loadSkillsByName(_ names: [String]) async {
        guard let skillHost = skillHost?() else { return }
        var syntheticEvents: [AgentEvent] = []
        var newlyActivated: [String] = []

        for skillName in names {
            guard !state.activatedSkillNames.contains(skillName) else { continue }
            guard !newlyActivated.contains(skillName) else { continue }

            let callID = "skill_load_\(skillName)_\(UUID().uuidString.prefix(8))"
            let argsJSON = SkillToolExecutor.loadSkillArgumentsJSON(name: skillName)

            let result: String
            do {
                result = capToolResult(
                    try await SkillToolExecutor.execute(
                        name: "load_skill",
                        argumentsJSON: argsJSON,
                        host: skillHost
                    )
                )
            } catch {
                continue
            }

            syntheticEvents.append(
                AgentEvent(
                    kind: .assistantResponse,
                    content: "",
                    toolCalls: [
                        ToolCallRecord(
                            id: callID,
                            name: "load_skill",
                            argumentsJSON: argsJSON
                        ),
                    ],
                    protected: true
                )
            )
            syntheticEvents.append(
                AgentEvent(
                    kind: .toolResult,
                    content: result,
                    toolCallID: callID,
                    protected: true
                )
            )
            newlyActivated.append(skillName)
        }

        guard !syntheticEvents.isEmpty else { return }
        let ok = await taskStore.commit(
            appendEvents: syntheticEvents,
            deleteEventIDs: [],
            mutate: { _ in }
        )
        if ok {
            state.activatedSkillNames.formUnion(newlyActivated)
        }
    }
}
