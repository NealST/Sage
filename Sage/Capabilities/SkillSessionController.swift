//
//  SkillSessionController.swift
//  Sage
//
//  Per-window skill tips, save jobs, extraction, and consolidate orchestration.
//  Keeps tip/save observation separate from AgentRuntime streaming state.
//

import Foundation

@MainActor
@Observable
final class SkillSessionController {
    let tips = SkillTipStore()
    var saveJobs: [SkillSaveJob] = []
    /// `/schedule-script` panel for this window.
    var scriptScheduleDraft: ScheduleScriptDraft?

    var suggestionGeneration: UInt64 = 0
    var extractionTaskIDs: Set<UUID> = []
    var inFlightExtractionTasks: [UUID: Task<Void, Never>] = [:]
    var persistJudgmentTasks: [UUID: Task<Void, Never>] = [:]
    var saveSuccessClearTasks: [UUID: Task<Void, Never>] = [:]
    var inFlightSaveTasks: [UUID: Task<Void, Never>] = [:]
    let extractionService = SkillExtractionService()
    weak var runtime: AgentRuntime?

    func attach(runtime: AgentRuntime) {
        self.runtime = runtime
    }

    /// Drops pending tips for this window (generation bump drops in-flight extraction tips).
    func invalidatePendingSuggestions() {
        suggestionGeneration &+= 1
        tips.dismissAll()
        scriptScheduleDraft = nil
    }

    /// Await confirmed skill writes before the owning window/session is released.
    func prepareForTeardown() async {
        invalidatePendingSuggestions()
        // Stop background extraction so it cannot enqueue tips or touch a torn-down host.
        let persistJudgments = Array(persistJudgmentTasks.values)
        persistJudgmentTasks.removeAll()
        for task in persistJudgments {
            task.cancel()
        }
        for task in persistJudgments {
            await task.value
        }

        let extractions = Array(inFlightExtractionTasks.values)
        for task in extractions {
            task.cancel()
        }
        for task in extractions {
            await task.value
        }
        inFlightExtractionTasks.removeAll()
        extractionTaskIDs.removeAll()

        let tasks = Array(inFlightSaveTasks.values)
        for task in tasks {
            await task.value
        }
        inFlightSaveTasks.removeAll()
        for clear in saveSuccessClearTasks.values {
            clear.cancel()
        }
        saveSuccessClearTasks.removeAll()
    }

    func enqueueConsolidateIfNeeded(candidates: [SkillRecallCandidate]) {
        guard candidates.count >= 2 else { return }
        tips.enqueueConsolidate(
            SkillConsolidateSuggestion(candidates: candidates)
        )
    }

    func dismissSkillSaveJob(_ jobID: UUID) {
        saveSuccessClearTasks[jobID]?.cancel()
        saveSuccessClearTasks[jobID] = nil
        saveJobs.removeAll { $0.id == jobID }
    }

    // MARK: - Extraction

    /// Plan-model persist gate after Review accept. Once per task; cancelled on teardown.
    func considerPersistenceAfterReview(
        for task: TaskRecord,
        judge: @escaping @MainActor () async -> Bool
    ) {
        guard persistJudgmentTasks[task.id] == nil else { return }
        let taskID = task.id
        persistJudgmentTasks[taskID] = Task { @MainActor [weak self] in
            defer { self?.persistJudgmentTasks[taskID] = nil }
            guard !Task.isCancelled else { return }
            let persist = await judge()
            guard persist, !Task.isCancelled else { return }
            self?.scheduleExtraction(for: task)
        }
    }

    func scheduleExtraction(
        for task: TaskRecord,
        mode: SkillExtractionMode = .automatic,
        userNote: String? = nil,
        presentImmediately: Bool = false
    ) {
        guard let runtime, canStartExtraction(for: task, mode: mode, runtime: runtime) else { return }
        extractionTaskIDs.insert(task.id)

        let snapshot = runtime.settings.snapshot(for: .plan)
        let catalog = extractionCatalog(runtime: runtime)
        let taskCopy = task
        let extractionService = extractionService
        let tipStore = tips
        let taskID = task.id
        let generation = suggestionGeneration
        let focusedProjectID = runtime.state.focusedProject?.id
        let note = userNote

        let work = Task.detached(priority: .utility) { [weak self] in
            defer {
                Task { @MainActor [weak self] in
                    self?.inFlightExtractionTasks[taskID] = nil
                    self?.extractionTaskIDs.remove(taskID)
                }
            }

            let result = await extractionService.analyze(
                task: taskCopy,
                existingSkills: catalog.existingSkills,
                settings: snapshot,
                mode: mode,
                userNote: note
            )
            guard !Task.isCancelled else { return }
            let suggestion = catalog.suggestion(from: result, taskID: taskCopy.id)
            await MainActor.run { [weak self] in
                self?.applyExtractionResult(
                    ExtractionApplyRequest(
                        suggestion: suggestion,
                        mode: mode,
                        presentImmediately: presentImmediately,
                        generation: generation,
                        focusedProjectID: focusedProjectID,
                        tipStore: tipStore
                    )
                )
            }
        }
        inFlightExtractionTasks[taskID] = work
    }

    func canStartExtraction(
        for task: TaskRecord,
        mode: SkillExtractionMode,
        runtime: AgentRuntime
    ) -> Bool {
        if mode == .automatic, task.events.count < 4 { return false }
        guard runtime.settings.isConfigured else { return false }
        guard !extractionTaskIDs.contains(task.id) else {
            if mode == .explicitRemember {
                runtime.applySkillExtractionPhase(
                    .failed(message: "Already identifying what to remember for this task.")
                )
            }
            return false
        }
        return true
    }

    nonisolated struct ExtractionCatalog {
        var inProjectContext: Bool
        var projectRootPath: String?
        var existingSkills: [SkillCatalogSummary]
        var pathByName: [String: String]
        var scopeByName: [String: SkillScope]

        func enhanceSuggestion(name: String, description: String, taskID: UUID) -> SkillSuggestion? {
            guard let path = pathByName[name], let scope = scopeByName[name] else { return nil }
            return SkillSuggestion(
                type: .enhance,
                skillName: name,
                skillDescription: description,
                scope: scope,
                allowsScopeChoice: false,
                projectRootPath: scope == .project ? projectRootPath : nil,
                targetSkillPath: path,
                sourceTaskID: taskID
            )
        }

        func suggestion(from result: SkillExtractionResult?, taskID: UUID) -> SkillSuggestion? {
            switch result {
            case .none, .some(.skip):
                return nil

            case .some(.newSkill(let name, let description)):
                if pathByName[name] != nil {
                    return enhanceSuggestion(name: name, description: description, taskID: taskID)
                }
                return SkillSuggestion(
                    type: .new,
                    skillName: name,
                    skillDescription: description,
                    scope: inProjectContext ? .project : .global,
                    allowsScopeChoice: inProjectContext,
                    projectRootPath: inProjectContext ? projectRootPath : nil,
                    targetSkillPath: nil,
                    sourceTaskID: taskID
                )

            case .some(.enhance(let existingName, let description)):
                return enhanceSuggestion(name: existingName, description: description, taskID: taskID)
            }
        }
    }

    func extractionCatalog(runtime: AgentRuntime) -> ExtractionCatalog {
        let inProjectContext = runtime.state.focusedProject != nil
        let catalogSkills = (runtime.skillCatalog?.skills ?? [])
            .filter(\.enabled)
            .filter { inProjectContext || $0.scope == .global }
        return ExtractionCatalog(
            inProjectContext: inProjectContext,
            projectRootPath: runtime.state.focusedProject?.rootURL.path,
            existingSkills: catalogSkills.map { skill in
                SkillCatalogSummary(name: skill.name, description: skill.description, scope: skill.scope)
            },
            pathByName: Dictionary(catalogSkills.map { ($0.name, $0.path) }) { first, _ in first },
            scopeByName: Dictionary(catalogSkills.map { ($0.name, $0.scope) }) { first, _ in first }
        )
    }

    struct ExtractionApplyRequest {
        var suggestion: SkillSuggestion?
        var mode: SkillExtractionMode
        var presentImmediately: Bool
        var generation: UInt64
        var focusedProjectID: UUID?
        var tipStore: SkillTipStore
    }

    func applyExtractionResult(_ request: ExtractionApplyRequest) {
        guard !Task.isCancelled else { return }
        guard let runtime,
              !runtime.state.isTornDown,
              suggestionGeneration == request.generation,
              runtime.state.focusedProject?.id == request.focusedProjectID else {
            if request.mode == .explicitRemember {
                self.runtime?.applySkillExtractionPhase(.idle)
            }
            return
        }
        if let suggestion = request.suggestion {
            if request.presentImmediately {
                request.tipStore.enqueueSaveImmediate(suggestion)
            } else {
                request.tipStore.enqueueSave(suggestion)
            }
            if request.mode == .explicitRemember {
                runtime.applySkillExtractionPhase(
                    .completed(
                        summary: suggestion.type == .enhance
                            ? """
                            Ready to update existing experience “\(suggestion.skillName)”. \
                            Confirm in the tip below.
                            """
                            : "Ready to save “\(suggestion.skillName)”. Confirm in the tip below."
                    )
                )
            }
            return
        }
        if request.mode == .explicitRemember {
            runtime.applySkillExtractionPhase(
                .failed(
                    message: "Couldn’t identify what to remember. Try again, or add a short note: /remember …"
                )
            )
        }
    }
}
