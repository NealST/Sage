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
    private(set) var saveJobs: [SkillSaveJob] = []

    private var suggestionGeneration: UInt64 = 0
    private var extractionTaskIDs: Set<UUID> = []
    private var inFlightExtractionTasks: [UUID: Task<Void, Never>] = [:]
    private var persistJudgmentTasks: [UUID: Task<Void, Never>] = [:]
    private var saveSuccessClearTasks: [UUID: Task<Void, Never>] = [:]
    private var inFlightSaveTasks: [UUID: Task<Void, Never>] = [:]
    private let extractionService = SkillExtractionService()
    private weak var runtime: AgentRuntime?

    func attach(runtime: AgentRuntime) {
        self.runtime = runtime
    }

    /// Drops pending tips for this window (generation bump drops in-flight extraction tips).
    func invalidatePendingSuggestions() {
        suggestionGeneration &+= 1
        tips.dismissAll()
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
        guard let runtime else { return }
        if mode == .automatic {
            guard task.events.count >= 4 else { return }
        }
        guard runtime.settings.isConfigured else { return }
        guard !extractionTaskIDs.contains(task.id) else {
            if mode == .explicitRemember {
                runtime.applySkillExtractionPhase(
                    .failed(message: "Already identifying what to remember for this task.")
                )
            }
            return
        }
        extractionTaskIDs.insert(task.id)

        let snapshot = runtime.settings.snapshot(for: .plan)

        let inProjectContext = runtime.state.focusedProject != nil
        let projectRootPath = runtime.state.focusedProject?.rootURL.path
        let catalogSkills = (runtime.skillCatalog?.skills ?? [])
            .filter(\.enabled)
            .filter { inProjectContext || $0.scope == .global }
        // Analyze needs metadata only — bodies are loaded later on confirm/compose.
        let existingSkills: [SkillCatalogSummary] = catalogSkills.map {
            SkillCatalogSummary(name: $0.name, description: $0.description, scope: $0.scope)
        }
        let pathByName = Dictionary(
            catalogSkills.map { ($0.name, $0.path) },
            uniquingKeysWith: { first, _ in first }
        )
        let scopeByName = Dictionary(
            catalogSkills.map { ($0.name, $0.scope) },
            uniquingKeysWith: { first, _ in first }
        )

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
                existingSkills: existingSkills,
                settings: snapshot,
                mode: mode,
                userNote: note
            )

            guard !Task.isCancelled else { return }

            func enhanceSuggestion(name: String, description: String) -> SkillSuggestion? {
                guard let path = pathByName[name], let scope = scopeByName[name] else { return nil }
                return SkillSuggestion(
                    type: .enhance,
                    skillName: name,
                    skillDescription: description,
                    scope: scope,
                    allowsScopeChoice: false,
                    projectRootPath: scope == .project ? projectRootPath : nil,
                    targetSkillPath: path,
                    sourceTaskID: taskCopy.id
                )
            }

            let suggestion: SkillSuggestion?
            switch result {
            case .none, .some(.skip):
                suggestion = nil
            case .some(.newSkill(let name, let description)):
                if pathByName[name] != nil {
                    suggestion = enhanceSuggestion(name: name, description: description)
                } else if inProjectContext {
                    suggestion = SkillSuggestion(
                        type: .new,
                        skillName: name,
                        skillDescription: description,
                        scope: .project,
                        allowsScopeChoice: true,
                        projectRootPath: projectRootPath,
                        targetSkillPath: nil,
                        sourceTaskID: taskCopy.id
                    )
                } else {
                    suggestion = SkillSuggestion(
                        type: .new,
                        skillName: name,
                        skillDescription: description,
                        scope: .global,
                        allowsScopeChoice: false,
                        projectRootPath: nil,
                        targetSkillPath: nil,
                        sourceTaskID: taskCopy.id
                    )
                }
            case .some(.enhance(let existingName, let description)):
                suggestion = enhanceSuggestion(name: existingName, description: description)
            }

            await MainActor.run { [weak self] in
                guard let self else { return }
                guard !Task.isCancelled else { return }
                guard let runtime = self.runtime,
                      !runtime.state.isTornDown,
                      self.suggestionGeneration == generation,
                      runtime.state.focusedProject?.id == focusedProjectID else {
                    if mode == .explicitRemember {
                        self.runtime?.applySkillExtractionPhase(.idle)
                    }
                    return
                }
                if let suggestion {
                    if presentImmediately {
                        tipStore.enqueueSaveImmediate(suggestion)
                    } else {
                        tipStore.enqueueSave(suggestion)
                    }
                    if mode == .explicitRemember {
                        runtime.applySkillExtractionPhase(
                            .completed(
                                summary: suggestion.type == .enhance
                                    ? "Ready to update existing experience “\(suggestion.skillName)”. Confirm in the tip below."
                                    : "Ready to save “\(suggestion.skillName)”. Confirm in the tip below."
                            )
                        )
                    }
                } else if mode == .explicitRemember {
                    runtime.applySkillExtractionPhase(
                        .failed(
                            message: "Couldn’t identify what to remember. Try again, or add a short note: /remember …"
                        )
                    )
                }
            }
        }
        inFlightExtractionTasks[taskID] = work
    }

    // MARK: - Save / consolidate jobs

    func startSuggestionSave(_ suggestion: SkillSuggestion) {
        runSaveJob(type: suggestion.type, skillName: suggestion.skillName) {
            try await self.confirmSuggestion(suggestion)
        }
    }

    func startConsolidate(_ suggestion: SkillConsolidateSuggestion) {
        guard let primary = suggestion.primary else { return }
        runSaveJob(type: .merge, skillName: primary.name) {
            try await self.confirmConsolidate(suggestion)
        }
    }

    private func runSaveJob(
        type: SkillSuggestion.SuggestionType,
        skillName: String,
        work: @escaping @MainActor () async throws -> Void
    ) {
        let job = SkillSaveJob(type: type, skillName: skillName, status: .running)
        saveJobs.insert(job, at: 0)
        let jobID = job.id

        let task = Task { @MainActor in
            defer { self.inFlightSaveTasks[jobID] = nil }
            do {
                try await work()
                self.updateSaveJob(jobID, status: .succeeded)
                self.scheduleSaveJobClear(jobID)
            } catch {
                self.saveSuccessClearTasks[jobID]?.cancel()
                self.saveSuccessClearTasks[jobID] = nil
                self.updateSaveJob(jobID, status: .failed(error.localizedDescription))
            }
        }
        inFlightSaveTasks[jobID] = task
    }

    private func updateSaveJob(_ jobID: UUID, status: SkillSaveJob.Status) {
        guard let index = saveJobs.firstIndex(where: { $0.id == jobID }) else { return }
        saveJobs[index].status = status
    }

    private func scheduleSaveJobClear(_ jobID: UUID) {
        saveSuccessClearTasks[jobID]?.cancel()
        saveSuccessClearTasks[jobID] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.dismissSkillSaveJob(jobID)
        }
    }

    private func requireRuntime() throws -> AgentRuntime {
        guard let runtime else { throw SkillCompositionError.hostUnavailable }
        if runtime.state.isTornDown { throw SkillCompositionError.sessionTornDown }
        return runtime
    }

    private func confirmSuggestion(_ suggestion: SkillSuggestion) async throws {
        let runtime = try requireRuntime()
        guard let sourceTask = try await runtime.taskRepository.loadTask(id: suggestion.sourceTaskID) else {
            throw SkillCompositionError.sourceTaskMissing
        }

        let snapshot = runtime.settings.snapshot(for: .plan)

        switch suggestion.type {
        case .new:
            if runtime.skillCatalog?.skills.contains(where: { $0.name == suggestion.skillName }) == true {
                throw SkillWriter.WriteError.alreadyExists(suggestion.skillName)
            }
            let draft = try await extractionService.composeNewSkill(
                skillName: suggestion.skillName,
                suggestedDescription: suggestion.skillDescription,
                task: sourceTask,
                settings: snapshot
            )
            // Re-check after compose — catalog may have changed during the LLM call.
            if runtime.skillCatalog?.skills.contains(where: { $0.name == suggestion.skillName }) == true {
                throw SkillWriter.WriteError.alreadyExists(suggestion.skillName)
            }
            let projectRoot = suggestion.projectRootPath.map { URL(fileURLWithPath: $0) }
            try await SkillWriter.createSkill(
                name: suggestion.skillName,
                description: draft.description,
                body: draft.body,
                scope: suggestion.scope,
                projectRoot: projectRoot
            )

        case .enhance:
            guard let path = suggestion.targetSkillPath,
                  FileManager.default.fileExists(atPath: path) else {
                throw SkillWriter.WriteError.skillNotFound(suggestion.skillName)
            }
            let existing = runtime.skillCatalog?.skills.first(where: { $0.path == path })
                ?? SkillRecord(
                    name: suggestion.skillName,
                    description: suggestion.skillDescription,
                    path: path,
                    enabled: true,
                    scope: suggestion.scope
                )
            let currentBody = await SkillRegistry.shared.readBody(for: existing)
            let draft = try await extractionService.composeEnhancedSkill(
                skillName: existing.name,
                currentDescription: existing.description,
                currentBody: currentBody,
                suggestedDescription: suggestion.skillDescription,
                task: sourceTask,
                settings: snapshot
            )
            try await SkillWriter.enhanceSkill(
                existingRecord: existing,
                description: draft.description,
                body: draft.body
            )

        case .merge:
            throw SkillCompositionError.unsupportedMergeViaSuggestion
        }

        await runtime.broadcastSkillsCatalogChange()
    }

    private func confirmConsolidate(_ suggestion: SkillConsolidateSuggestion) async throws {
        let runtime = try requireRuntime()
        guard let primary = suggestion.primary else {
            throw SkillWriter.WriteError.skillNotFound("merge target")
        }
        guard let primaryRecord = runtime.skillCatalog?.skills.first(where: { $0.path == primary.path }) else {
            throw SkillWriter.WriteError.skillNotFound(primary.name)
        }

        let snapshot = runtime.settings.snapshot(for: .plan)

        var inputs: [(name: String, description: String, body: String)] = []
        for candidate in suggestion.candidates {
            let record = runtime.skillCatalog?.skills.first(where: { $0.path == candidate.path })
            let body: String
            if let record {
                body = await SkillRegistry.shared.readBody(for: record)
            } else {
                body = ""
            }
            inputs.append((candidate.name, candidate.description, body))
        }

        let draft = try await extractionService.composeMergedSkills(
            primaryName: primary.name,
            skills: inputs,
            settings: snapshot
        )

        try await SkillWriter.enhanceSkill(
            existingRecord: primaryRecord,
            description: draft.description,
            body: draft.body
        )

        var deleteFailures: [String] = []
        for candidate in suggestion.candidates where candidate.path != primary.path {
            guard let catalog = runtime.skillCatalog,
                  let record = catalog.skills.first(where: { $0.path == candidate.path }) else {
                continue
            }
            do {
                try await catalog.deleteSkill(record)
            } catch {
                deleteFailures.append(candidate.name)
            }
        }

        await runtime.broadcastSkillsCatalogChange()

        if !deleteFailures.isEmpty {
            throw SkillCompositionError.mergeCleanupFailed(deleteFailures)
        }
    }

}

/// Lightweight catalog entry for extraction analysis (no body).
nonisolated struct SkillCatalogSummary: Sendable {
    let name: String
    let description: String
    let scope: SkillScope
}
