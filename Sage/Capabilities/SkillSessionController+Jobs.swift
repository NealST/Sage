//
//  SkillSessionController+Jobs.swift
//  Sage
//

import Foundation

extension SkillSessionController {
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

    func runSaveJob(
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

    func updateSaveJob(_ jobID: UUID, status: SkillSaveJob.Status) {
        guard let index = saveJobs.firstIndex(where: { $0.id == jobID }) else { return }
        saveJobs[index].status = status
    }

    func scheduleSaveJobClear(_ jobID: UUID) {
        saveSuccessClearTasks[jobID]?.cancel()
        saveSuccessClearTasks[jobID] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.dismissSkillSaveJob(jobID)
        }
    }

    func requireRuntime() throws -> AgentRuntime {
        guard let runtime else { throw SkillCompositionError.hostUnavailable }
        if runtime.state.isTornDown { throw SkillCompositionError.sessionTornDown }
        return runtime
    }

    func confirmSuggestion(_ suggestion: SkillSuggestion) async throws {
        let runtime = try requireRuntime()
        guard let sourceTask = try await runtime.taskRepository.loadTask(id: suggestion.sourceTaskID) else {
            throw SkillCompositionError.sourceTaskMissing
        }
        let snapshot = runtime.settings.snapshot(for: .plan)
        switch suggestion.type {
        case .new:
            try await confirmNewSkill(suggestion, sourceTask: sourceTask, runtime: runtime, snapshot: snapshot)

        case .enhance:
            try await confirmEnhanceSkill(suggestion, sourceTask: sourceTask, runtime: runtime, snapshot: snapshot)

        case .merge:
            throw SkillCompositionError.unsupportedMergeViaSuggestion
        }
        await runtime.broadcastSkillsCatalogChange()
    }

    func confirmNewSkill(
        _ suggestion: SkillSuggestion,
        sourceTask: TaskRecord,
        runtime: AgentRuntime,
        snapshot: ModelSettingsSnapshot
    ) async throws {
        if runtime.skillCatalog?.skills.contains(where: { $0.name == suggestion.skillName }) == true {
            throw SkillWriter.WriteError.alreadyExists(suggestion.skillName)
        }
        let draft = try await extractionService.composeNewSkill(
            skillName: suggestion.skillName,
            suggestedDescription: suggestion.skillDescription,
            task: sourceTask,
            settings: snapshot
        )
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
    }

    func confirmEnhanceSkill(
        _ suggestion: SkillSuggestion,
        sourceTask: TaskRecord,
        runtime: AgentRuntime,
        snapshot: ModelSettingsSnapshot
    ) async throws {
        guard let path = suggestion.targetSkillPath,
              FileManager.default.fileExists(atPath: path) else {
            throw SkillWriter.WriteError.skillNotFound(suggestion.skillName)
        }
        let existing = runtime.skillCatalog?.skills.first { $0.path == path }
            ?? SkillRecord(
                name: suggestion.skillName,
                description: suggestion.skillDescription,
                path: path,
                enabled: true,
                scope: suggestion.scope
            )
        let currentBody = await SkillRegistry.shared.readBody(for: existing)
        let draft = try await extractionService.composeEnhancedSkill(
            SkillEnhanceInput(
                skillName: existing.name,
                currentDescription: existing.description,
                currentBody: currentBody,
                suggestedDescription: suggestion.skillDescription,
                task: sourceTask,
                settings: snapshot
            )
        )
        try await SkillWriter.enhanceSkill(
            existingRecord: existing,
            description: draft.description,
            body: draft.body
        )
    }

    func confirmConsolidate(_ suggestion: SkillConsolidateSuggestion) async throws {
        let runtime = try requireRuntime()
        guard let primary = suggestion.primary else {
            throw SkillWriter.WriteError.skillNotFound("merge target")
        }
        guard let primaryRecord = runtime.skillCatalog?.skills.first(where: { $0.path == primary.path }) else {
            throw SkillWriter.WriteError.skillNotFound(primary.name)
        }

        let snapshot = runtime.settings.snapshot(for: .plan)

        let inputs = await mergeInputs(for: suggestion, runtime: runtime)
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
        let deleteFailures = await deleteMergedCandidates(suggestion, primaryPath: primary.path, runtime: runtime)
        await runtime.broadcastSkillsCatalogChange()
        if !deleteFailures.isEmpty {
            throw SkillCompositionError.mergeCleanupFailed(deleteFailures)
        }
    }

    func mergeInputs(
        for suggestion: SkillConsolidateSuggestion,
        runtime: AgentRuntime
    ) async -> [SkillMergeInput] {
        var inputs: [SkillMergeInput] = []
        for candidate in suggestion.candidates {
            let record = runtime.skillCatalog?.skills.first { $0.path == candidate.path }
            let body: String
            if let record {
                body = await SkillRegistry.shared.readBody(for: record)
            } else {
                body = ""
            }
            inputs.append(
                SkillMergeInput(
                    name: candidate.name,
                    description: candidate.description,
                    body: body
                )
            )
        }
        return inputs
    }

    func deleteMergedCandidates(
        _ suggestion: SkillConsolidateSuggestion,
        primaryPath: String,
        runtime: AgentRuntime
    ) async -> [String] {
        var deleteFailures: [String] = []
        for candidate in suggestion.candidates where candidate.path != primaryPath {
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
        return deleteFailures
    }
}

/// Lightweight catalog entry for extraction analysis (no body).
nonisolated struct SkillCatalogSummary: Sendable {
    let name: String
    let description: String
    let scope: SkillScope
}
