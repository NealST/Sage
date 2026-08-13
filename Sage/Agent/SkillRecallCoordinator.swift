//
//  SkillRecallCoordinator.swift
//  Sage
//
//  Skill match / choose / auto-load / turn cache.
//

import Foundation

/// Per-window skill recall state and orchestration.
@MainActor
final class SkillRecallCoordinator {
    private let state: AgentSessionState
    private let skills: SkillSessionController
    private let skillCatalog: () -> SkillCatalog?
    private let taskStore: AgentTaskStore
    private var skillHost: (() -> SkillToolHost?)?
    private let classifier = IntentComplexityClassifier()

    /// Cached skill appendix for the current user turn.
    private(set) var cachedResult: SkillCatalog.SkillAppendixResult?
    /// Query that produced `cachedResult` (for plan-step reuse).
    private(set) var cachedQuery: String?
    /// When set, system prompt asks the model to decompose multi-intent work.
    private(set) var complexIntentHintActive = false

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
        complexIntentHintActive = false
    }

    func rememberCache(_ result: SkillCatalog.SkillAppendixResult, query: String) {
        cachedResult = result
        cachedQuery = query
    }

    /// Resolves skill recall for a query.
    /// - Returns: `false` when paused for user skill choice (only if `pauseForAmbiguity`).
    @discardableResult
    func prepareSkillsForTurn(
        query: String,
        pauseForAmbiguity: Bool
    ) async -> Bool {
        guard let skillCatalog = skillCatalog() else { return true }

        if pauseForAmbiguity {
            let complexity = await classifier.classify(query)
            if complexity == .complex {
                complexIntentHintActive = true
                let appendix = await skillCatalog.skillsPromptAppendix(
                    for: query,
                    skipMatching: true
                )
                rememberCache(appendix, query: query)
                return true
            }
        } else {
            if Self.shouldSkipPlanStepMatching(query) {
                complexIntentHintActive = false
                let appendix = await skillCatalog.skillsPromptAppendix(
                    for: query,
                    skipMatching: true
                )
                rememberCache(appendix, query: query)
                return true
            }
            if let cached = cachedResult,
               let prior = cachedQuery,
               Self.skillQueriesSimilar(query, prior) {
                complexIntentHintActive = false
                return await applySkillRecall(
                    cached,
                    query: query,
                    skillCatalog: skillCatalog,
                    pauseForAmbiguity: false
                )
            }
        }

        complexIntentHintActive = false
        let skillResult = await skillCatalog.skillsPromptAppendix(for: query)
        rememberCache(skillResult, query: query)
        return await applySkillRecall(
            skillResult,
            query: query,
            skillCatalog: skillCatalog,
            pauseForAmbiguity: pauseForAmbiguity
        )
    }

    /// After the user picks a skill from an ambiguous tip.
    func refreshCatalogWithoutRematch(query: String) async {
        guard let appendix = await skillCatalog()?.skillsPromptAppendix(
            for: query,
            skipMatching: true
        ) else { return }
        rememberCache(appendix, query: query)
    }

    func loadSkillsByName(_ names: [String]) async {
        guard let skillHost = skillHost?() else { return }
        var syntheticEvents: [AgentEvent] = []
        var newlyActivated: [String] = []

        for skillName in names {
            guard !state.activatedSkillNames.contains(skillName) else { continue }
            guard !newlyActivated.contains(skillName) else { continue }

            let callID = "auto_skill_\(skillName)_\(UUID().uuidString.prefix(8))"
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

    // MARK: - Private

    private func applySkillRecall(
        _ skillResult: SkillCatalog.SkillAppendixResult,
        query: String,
        skillCatalog: SkillCatalog,
        pauseForAmbiguity: Bool
    ) async -> Bool {
        let toLoad = skillResult.recommendedSkills.filter {
            !state.activatedSkillNames.contains($0)
        }
        switch toLoad.count {
        case 0:
            return true
        case 1:
            await loadSkillsByName(toLoad)
            return true
        default:
            let candidates = toLoad.compactMap { name -> SkillRecallCandidate? in
                guard let skill = skillCatalog.enabledSkills.first(where: { $0.name == name }) else {
                    return nil
                }
                return SkillRecallCandidate(skill: skill)
            }
            guard candidates.count >= 2 else {
                await loadSkillsByName(candidates.map(\.name))
                return true
            }

            if pauseForAmbiguity {
                let choice = SkillActivationChoice(candidates: candidates, queryText: query)
                skills.tips.enqueueChoose(choice)
                state.phase = .awaitingSkillChoice(choice)
                return false
            }

            skills.enqueueConsolidateIfNeeded(candidates: candidates)
            return true
        }
    }

    private static func shouldSkipPlanStepMatching(_ title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count < 16 { return true }
        let words = trimmed.split(whereSeparator: \.isWhitespace)
        if words.count <= 2 { return true }
        let lower = trimmed.lowercased()
        let prefixes = ["run ", "call ", "execute ", "invoke ", "use ", "open "]
        if prefixes.contains(where: { lower.hasPrefix($0) }) && words.count <= 4 {
            return true
        }
        return false
    }

    private static func skillQueriesSimilar(_ a: String, _ b: String) -> Bool {
        let na = normalizedSkillQuery(a)
        let nb = normalizedSkillQuery(b)
        guard !na.isEmpty, !nb.isEmpty else { return false }
        if na == nb { return true }
        if na.contains(nb) || nb.contains(na) { return true }
        let ta = Set(na.split(separator: " ").map(String.init))
        let tb = Set(nb.split(separator: " ").map(String.init))
        guard !ta.isEmpty, !tb.isEmpty else { return false }
        let overlap = ta.intersection(tb).count
        return Double(overlap) / Double(min(ta.count, tb.count)) >= 0.7
    }

    private static func normalizedSkillQuery(_ value: String) -> String {
        value
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace || $0.isPunctuation || $0.isNewline })
            .joined(separator: " ")
    }
}
