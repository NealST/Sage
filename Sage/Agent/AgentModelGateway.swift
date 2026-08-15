//
//  AgentModelGateway.swift
//  Sage
//
//  Model request assembly + streaming.
//

import Foundation

struct PreparedModelRequest: Sendable {
    let events: [AgentEvent]
    let tools: [ToolDefinition]
    let settings: ModelSettingsSnapshot
}

/// Owns the remote `ModelClient` and builds/streams chat completions.
@MainActor
final class AgentModelGateway {
    private let modelClient = ModelClient()
    private let state: AgentSessionState
    private let settings: ModelSettings
    private let tools: ToolRegistry
    private let systemPrompt: String
    private let skillRecall: SkillRecallCoordinator
    private let skillCatalog: () -> SkillCatalog?
    private let mcpToolDefinitions: () -> [ToolDefinition]
    private let taskRepository: any TaskRepository
    private let projectPromptAppendix: () -> String
    private let streaming: StreamingTextPump

    init(
        state: AgentSessionState,
        settings: ModelSettings,
        tools: ToolRegistry,
        systemPrompt: String,
        skillRecall: SkillRecallCoordinator,
        skillCatalog: @escaping () -> SkillCatalog?,
        mcpToolDefinitions: @escaping () -> [ToolDefinition],
        taskRepository: any TaskRepository,
        projectPromptAppendix: @escaping () -> String,
        streaming: StreamingTextPump
    ) {
        self.state = state
        self.settings = settings
        self.tools = tools
        self.systemPrompt = systemPrompt
        self.skillRecall = skillRecall
        self.skillCatalog = skillCatalog
        self.mcpToolDefinitions = mcpToolDefinitions
        self.taskRepository = taskRepository
        self.projectPromptAppendix = projectPromptAppendix
        self.streaming = streaming
    }

    func setRetryStatusHandler(_ handler: @escaping @MainActor (RetryStatus) -> Void) async {
        await modelClient.setRetryStatusHandler(handler)
    }

    /// Single source of truth for tools exposed to the model (and UI).
    func availableToolDefinitions(includeSkills: Bool = true) async -> [ToolDefinition] {
        var defs = tools.definitions + mcpToolDefinitions()
        guard includeSkills else { return defs }

        let skillResult: SkillCatalog.SkillAppendixResult?
        if let cached = skillRecall.cachedResult {
            skillResult = cached
        } else {
            skillResult = await skillCatalog()?.skillsPromptAppendix()
        }

        if skillResult?.needsLoadSkillTool == true {
            defs.append(SkillToolExecutor.loadSkillDefinition)
        }
        if !state.activatedSkillNames.isEmpty {
            defs.append(SkillToolExecutor.loadSkillResourceDefinition)
            defs.append(SkillToolExecutor.runSkillScriptDefinition)
        }
        defs.append(SkillToolExecutor.saveSkillDefinition)
        return SkillToolPolicy.filterDefinitions(
            defs,
            activatedSkillNames: state.activatedSkillNames,
            enabledSkills: skillCatalog()?.enabledSkills ?? []
        )
    }

    func prepareRequest(includeTools: Bool) async -> PreparedModelRequest {
        let snapshot = ModelSettingsSnapshot(
            baseURL: settings.baseURL,
            model: settings.model,
            apiKey: settings.apiKey
        )

        let skillResult: SkillCatalog.SkillAppendixResult?
        if let cached = skillRecall.cachedResult {
            skillResult = cached
        } else {
            let latestUserMessage = state.events.last(where: { $0.kind == .userInput })?.content ?? ""
            let computed = await skillCatalog()?.skillsPromptAppendix()
            if let computed {
                skillRecall.rememberCache(computed, query: latestUserMessage)
            }
            skillResult = computed
        }

        let skillsAppendix = skillResult?.text ?? ""
        let relatedAppendix = await relatedContextAppendix()
        var modelEvents = [
            AgentEvent(
                kind: .systemInstruction,
                content: systemPrompt
                    + projectPromptAppendix()
                    + skillsAppendix
                    + relatedAppendix
            )
        ]
        modelEvents.append(contentsOf: ContextBudget.select(from: state.events))

        let toolDefinitions: [ToolDefinition]
        if includeTools {
            toolDefinitions = await availableToolDefinitions(includeSkills: true)
        } else {
            toolDefinitions = []
        }

        return PreparedModelRequest(
            events: modelEvents,
            tools: toolDefinitions,
            settings: snapshot
        )
    }

    func streamComplete(includeTools: Bool = true) async throws -> ModelTurn {
        let req = await prepareRequest(includeTools: includeTools)
        let stream = try await modelClient.streamComplete(
            events: req.events,
            tools: req.tools,
            settings: req.settings
        )

        state.retryState = nil

        var contentChunks: [String] = []
        var toolCallBuilders: [Int: ToolCallBuilder] = [:]
        var usage = TokenUsage()

        streaming.clear()

        for try await delta in stream {
            try Task.checkCancellation()

            switch delta {
            case .text(let chunk):
                contentChunks.append(chunk)
                streaming.publish(contentChunks.joined())

            case .toolCallDelta(let index, let id, let name, let arguments):
                var builder = toolCallBuilders[index] ?? ToolCallBuilder()
                if let id { builder.id = id }
                if let name { builder.name = name }
                if let arguments { builder.arguments += arguments }
                toolCallBuilders[index] = builder

            case .usage(let input, let output):
                usage.input = input
                usage.output = output

            case .done:
                break
            }
        }

        let contentBuffer = contentChunks.joined()
        streaming.flush(contentBuffer)
        state.addTokenUsage(usage)

        let toolCalls = toolCallBuilders.keys.sorted().compactMap { index -> ToolCallProposal? in
            guard let builder = toolCallBuilders[index],
                  let id = builder.id,
                  let name = builder.name
            else { return nil }
            return ToolCallProposal(id: id, name: name, argumentsJSON: builder.arguments)
        }

        let content = contentBuffer.isEmpty ? nil : contentBuffer
        return ModelTurn(content: content, toolCalls: toolCalls, usage: usage)
    }

    // MARK: - Related context

    private func relatedContextAppendix() async -> String {
        guard let task = state.activeTask else { return "" }
        let relatedIDs = Array(
            task.relatedTaskIDs
                .filter { $0 != task.id }
                .prefix(3)
        )
        guard !relatedIDs.isEmpty else { return "" }

        let snippets: [RelatedTaskContextSnippet]
        do {
            snippets = try await taskRepository.loadRelatedContextSnippets(
                ids: relatedIDs,
                projectID: state.focusedProject?.id
            )
        } catch {
            return ""
        }
        guard !snippets.isEmpty else { return "" }

        var lines = ["", "## Related prior work", "Use only if relevant to the current request:"]
        for related in snippets {
            let topic = related.topic?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            let summary = related.summary?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            let title = topic ?? summary ?? "Prior task"
            lines.append("- \(title)")
            if let abstract = related.abstract?.trimmingCharacters(in: .whitespacesAndNewlines),
               !abstract.isEmpty {
                lines.append("  Intent: \(abstract)")
            }
            for turn in related.recentDialogue {
                let clipped = String(
                    turn.content.trimmingCharacters(in: .whitespacesAndNewlines).prefix(220)
                )
                guard !clipped.isEmpty else { continue }
                switch turn.kind {
                case .user:
                    lines.append("  User: \(clipped)")
                case .assistant:
                    lines.append("  Assistant: \(clipped)")
                }
            }
        }
        return lines.count > 3 ? lines.joined(separator: "\n") : ""
    }
}

/// Accumulates streamed tool-call fragments by index.
struct ToolCallBuilder {
    var id: String?
    var name: String?
    var arguments: String = ""
}
