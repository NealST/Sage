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
    let occupancy: Double
}

/// Owns the remote `ModelClient` and builds/streams chat completions.
@MainActor
final class AgentModelGateway {
    let modelClient = ModelClient()
    let state: AgentSessionState
    let settings: ModelSettings
    let tools: ToolRegistry
    let systemPrompt: String
    let skillRecall: SkillRecallCoordinator
    let skillCatalog: () -> SkillCatalog?
    let mcpToolDefinitions: () -> [ToolDefinition]
    let taskRepository: any TaskRepository
    let projectPromptAppendix: () -> String
    let streaming: StreamingTextPump
    var relatedContextCache: RelatedContextCache?
    weak var compact: ContextCompactor?

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

    func bind(compact: ContextCompactor) {
        self.compact = compact
    }

    func setRetryStatusHandler(_ handler: @escaping @MainActor (RetryStatus) -> Void) async {
        await modelClient.setRetryStatusHandler(handler)
    }

    /// Single source of truth for tools exposed to the model (and UI).
    func availableToolDefinitions(includeSkills: Bool = true) -> [ToolDefinition] {
        let mcpDefinitions = MCPToolGroupTool.groupedDefinitions(
            mcpToolDefinitions(),
            unlockedServerNames: state.activeTask?.unlockedMCPServerNames ?? []
        )
        var defs = tools.definitions + mcpDefinitions
        if state.activeTask?.workingMemory?.hasContent == true {
            defs.append(RecallTaskTranscriptTool.definition)
        }
        defs.append(ExploreSubagentTool.definition)
        if state.activeTask?.workPlan?.kind == .act {
            defs.append(ManageTodoListTool.definition)
        }
        guard includeSkills else { return defs }

        let skillResult: SkillCatalog.SkillAppendixResult?
        if let cached = skillRecall.cachedResult {
            skillResult = cached
        } else {
            skillResult = skillCatalog()?.skillsPromptAppendix()
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
        let snapshot = settings.snapshot(for: .execute)

        let skillResult: SkillCatalog.SkillAppendixResult?
        if let cached = skillRecall.cachedResult {
            skillResult = cached
        } else {
            let latestUserMessage = state.events.last { $0.kind == .userInput }?.content ?? ""
            let computed = skillCatalog()?.skillsPromptAppendix()
            if let computed {
                skillRecall.rememberCache(computed, query: latestUserMessage)
            }
            skillResult = computed
        }

        let toolDefinitions: [ToolDefinition]
        if includeTools {
            toolDefinitions = availableToolDefinitions(includeSkills: true)
        } else {
            toolDefinitions = []
        }

        var resolvedTools = toolDefinitions
        var assembly = await assemblePrompt(
            tools: resolvedTools,
            workingMemory: state.activeTask?.workingMemory,
            skillResult: skillResult
        )
        if assembly.didExceedBudget {
            _ = await compact?.handleOverflow(tools: resolvedTools)
            if includeTools {
                resolvedTools = availableToolDefinitions(includeSkills: true)
            }
            assembly = await assemblePrompt(
                tools: resolvedTools,
                workingMemory: state.activeTask?.workingMemory,
                skillResult: skillResult
            )
        }

        return PreparedModelRequest(
            events: assembly.events,
            tools: resolvedTools,
            settings: snapshot,
            occupancy: assembly.occupancy
        )
    }

    /// Occupancy as if the fold were expanded. Used to discard a snapshot when
    /// the window grew enough that raw history already fits.
    func occupancyIgnoringWorkingMemory() async -> Double {
        let toolDefinitions = availableToolDefinitions(includeSkills: true)
        let skillResult = skillRecall.cachedResult
        let assembly = await assemblePrompt(
            tools: toolDefinitions,
            workingMemory: nil,
            skillResult: skillResult
        )
        return assembly.occupancy
    }

    /// Non-streaming compact pass. Same execute model; no tool calls.
    func completeForCompaction(
        events: [AgentEvent],
        tools: [ToolDefinition]
    ) async throws -> String {
        let snapshot = settings.snapshot(for: .execute)
        let turn = try await modelClient.complete(
            events: events,
            tools: tools,
            settings: snapshot,
            toolChoice: "none",
            temperature: 0
        )
        state.addTokenUsage(turn.usage)
        return turn.content ?? ""
    }

    /// Non-streaming completion for plan / review sub-agents. Does not publish tokens.
    func completeUnstreamed(system: String, user: String, role: ModelRole) async throws -> String {
        let snapshot = settings.snapshot(for: role)
        let turn = try await modelClient.complete(
            events: [
                AgentEvent(kind: .systemInstruction, content: system),
                AgentEvent(kind: .userInput, content: user),
            ],
            tools: [],
            settings: snapshot
        )
        state.addTokenUsage(turn.usage)
        return turn.content ?? ""
    }

    func reviewFeedbackAppendix() -> String {
        guard let feedback = state.reviewFeedback?.trimmingCharacters(in: .whitespacesAndNewlines),
              !feedback.isEmpty
        else { return "" }
        return """


        ## Reviewer feedback
        The previous execute pass was not accepted. Address this, then finish:
        \(feedback)
        """
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

        for try await delta in stream {
            try Task.checkCancellation()

            switch delta {
            case .text(let chunk):
                contentChunks.append(chunk)
                streaming.publish(TextToolCallParser.visibleText(in: contentChunks.joined()))

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
        state.addTokenUsage(usage)

        let structuredCalls = toolCallBuilders.keys.sorted().compactMap { index -> ToolCallProposal? in
            guard let builder = toolCallBuilders[index],
                  let id = builder.id,
                  let name = builder.name
            else { return nil }
            return ToolCallProposal(id: id, name: name, argumentsJSON: builder.arguments)
        }
        let recovered = TextToolCallParser.recover(from: contentBuffer, existing: structuredCalls)
        streaming.flush(recovered.content ?? "")
        compact?.considerBackground(occupancy: req.occupancy, tools: req.tools)
        return ModelTurn(content: recovered.content, toolCalls: recovered.calls, usage: usage)
    }
}
