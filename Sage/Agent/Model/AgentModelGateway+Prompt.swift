//
//  AgentModelGateway+Prompt.swift
//  Sage
//

import Foundation

extension AgentModelGateway {
    func assemblePrompt(
        tools: [ToolDefinition],
        workingMemory: TaskWorkingMemory?,
        skillResult: SkillCatalog.SkillAppendixResult?
    ) async -> PromptAssembly {
        let snapshot = settings.snapshot(for: .execute)
        let budget = PromptBudget.forModel(snapshot.model)
            .deductingToolDefinitions(tools)
        return ContextBudget.assemble(
            PromptLayout(
                budget: budget,
                baseInstructions: systemPrompt,
                projectAppendix: projectPromptAppendix(),
                capabilityReminder: ExecuteCapabilityReminder.make(
                    planKind: state.activeTask?.workPlan?.kind,
                    activatedSkillNames: state.activatedSkillNames,
                    mcpServerNames: ExecuteCapabilityReminder.mcpServerNames(from: tools),
                    todos: state.activeTask?.todos ?? []
                ),
                workPlanAppendix: state.activeTask?.workPlan?.promptAppendix ?? "",
                todoAppendix: ManageTodoListTool.promptAppendix(state.activeTask?.todos ?? []),
                workingMemory: workingMemory,
                reviewFeedback: reviewFeedbackAppendix(),
                skillsCatalog: skillResult?.text ?? "",
                relatedSnippets: await relatedContextSnippets(),
                events: state.events
            )
        )
    }

    // MARK: - Related context

    func relatedContextSnippets() async -> [RelatedTaskContextSnippet] {
        guard let task = state.activeTask else { return [] }
        let relatedIDs = Array(
            task.relatedTaskIDs
                .filter { $0 != task.id }
                .prefix(3)
        )
        guard !relatedIDs.isEmpty else { return [] }
        if let cached = relatedContextCache,
           cached.taskID == task.id,
           cached.relatedIDs == relatedIDs {
            return cached.snippets
        }

        let snippets: [RelatedTaskContextSnippet]
        do {
            snippets = try await taskRepository.loadRelatedContextSnippets(
                ids: relatedIDs,
                projectID: state.focusedProject?.id
            )
        } catch {
            return []
        }
        relatedContextCache = RelatedContextCache(
            taskID: task.id,
            relatedIDs: relatedIDs,
            snippets: snippets
        )
        return snippets
    }
}

struct RelatedContextCache {
    var taskID: UUID
    var relatedIDs: [UUID]
    var snippets: [RelatedTaskContextSnippet]
}

/// Accumulates streamed tool-call fragments by index.
struct ToolCallBuilder {
    var id: String?
    var name: String?
    var arguments: String = ""
}
