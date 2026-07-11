//
//  AgentRuntime.swift
//  Sage
//

import Foundation

@MainActor
@Observable
final class AgentRuntime {
    private(set) var sessions: [ChatSession] = []
    private(set) var activeSessionID: UUID?
    private(set) var phase: AgentPhase = .idle
    private(set) var lastAssistantText: String?

    var messages: [ChatMessage] {
        activeSession?.messages ?? []
    }

    var activeSession: ChatSession? {
        guard let activeSessionID else { return nil }
        return sessions.first(where: { $0.id == activeSessionID })
    }

    var availableTools: [ToolDefinition] {
        tools.definitions + (capabilities?.mcpToolDefinitions() ?? [])
    }

    private let modelClient = ModelClient()
    private let tools: ToolRegistry
    private let sessionStore = SessionStore()
    private let settings: ModelSettings
    private weak var capabilities: CapabilityStore?

    private let systemPrompt = """
    You are Sage, a native macOS agent that helps the user get work done on their Mac.
    Prefer using tools for real actions (files, clipboard, apps, notifications).
    Keep plans small and concrete. Expand ~ paths. Stay inside the user's home directory for files.
    When rewriting text for the clipboard, use get_clipboard / set_clipboard.
    After tools run, you will see their results — then give a short clear summary of what happened.
    Reply in the same language the user uses.
    """

    init(
        settings: ModelSettings = .shared,
        tools: ToolRegistry = .makeDefault(),
        capabilities: CapabilityStore? = nil
    ) {
        self.settings = settings
        self.tools = tools
        self.capabilities = capabilities
    }

    func bootstrap() async {
        if let snapshot = await sessionStore.load(), !snapshot.sessions.isEmpty {
            sessions = snapshot.sessions.sorted { $0.updatedAt > $1.updatedAt }
            activeSessionID = snapshot.activeSessionID ?? sessions.first?.id
            restorePhaseFromActiveSession()
        } else {
            let session = ChatSession()
            sessions = [session]
            activeSessionID = session.id
            phase = .idle
            await persist()
        }
    }

    func createSession() {
        syncPhaseIntoActiveSession()
        let session = ChatSession()
        sessions.insert(session, at: 0)
        activeSessionID = session.id
        phase = .idle
        lastAssistantText = nil
        Task { await persist() }
    }

    func selectSession(_ id: UUID) {
        guard id != activeSessionID else { return }
        // Preserve pending plan on the session being left.
        syncPhaseIntoActiveSession()
        activeSessionID = id
        restorePhaseFromActiveSession()
        Task { await persist() }
    }

    func deleteSession(_ id: UUID) {
        sessions.removeAll { $0.id == id }
        if sessions.isEmpty {
            let session = ChatSession()
            sessions = [session]
            activeSessionID = session.id
            phase = .idle
            lastAssistantText = nil
        } else if activeSessionID == id {
            activeSessionID = sessions.first?.id
            restorePhaseFromActiveSession()
        }
        Task { await persist() }
    }

    func clearActiveSession() async {
        guard let id = activeSessionID,
              let index = sessions.firstIndex(where: { $0.id == id })
        else { return }
        sessions[index].messages = []
        sessions[index].pendingPlan = nil
        sessions[index].title = "New Chat"
        sessions[index].updatedAt = .now
        phase = .idle
        lastAssistantText = nil
        await persist()
    }

    func submit(_ userText: String) async {
        let trimmed = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard settings.isConfigured else {
            phase = .failed(message: ModelClientError.notConfigured.localizedDescription)
            return
        }
        ensureActiveSession()

        appendMessage(ChatMessage(role: .user, content: trimmed))
        updateTitleIfNeeded(from: trimmed)
        phase = .thinking
        lastAssistantText = nil
        mutateActive { $0.pendingPlan = nil }
        await persist()

        do {
            let turn = try await requestModel()
            await handleTurn(turn)
        } catch {
            phase = .failed(message: error.localizedDescription)
            await persist()
        }
    }

    func confirmPendingPlan() async {
        guard case .awaitingConfirmation(var plan) = phase else { return }
        phase = .executing(plan)

        for index in plan.steps.indices {
            plan.steps[index].status = .running
            phase = .executing(plan)
            mutateActive { $0.pendingPlan = plan }

            let step = plan.steps[index]
            do {
                let result: String
                if step.toolName.hasPrefix("mcp__"), let capabilities {
                    result = try await capabilities.callMCPTool(
                        qualifiedName: step.toolName,
                        argumentsJSON: step.argumentsJSON
                    )
                } else if let tool = tools.tool(named: step.toolName) {
                    result = try await tool.call(argumentsJSON: step.argumentsJSON)
                } else {
                    throw ToolError.operationFailed("Unknown tool: \(step.toolName)")
                }
                plan.steps[index].status = .succeeded
                plan.steps[index].result = result
                appendMessage(ChatMessage(role: .tool, content: result, toolCallID: step.toolCallID))
            } catch {
                plan.steps[index].status = .failed
                plan.steps[index].result = error.localizedDescription
                appendMessage(
                    ChatMessage(
                        role: .tool,
                        content: "ERROR: \(error.localizedDescription)",
                        toolCallID: step.toolCallID
                    )
                )
            }
            phase = .executing(plan)
            mutateActive { $0.pendingPlan = plan }
        }

        mutateActive { $0.pendingPlan = nil }
        await persist()
        phase = .thinking

        do {
            let turn = try await requestModel(includeTools: false)
            let summary = turn.content?.trimmingCharacters(in: .whitespacesAndNewlines)
            let text: String
            if let summary, !summary.isEmpty {
                text = summary
            } else {
                let fallback = plan.steps.compactMap(\.result).joined(separator: "\n")
                text = fallback.isEmpty ? "Done." : fallback
            }
            appendMessage(ChatMessage(role: .assistant, content: text))
            lastAssistantText = text
            phase = .completed(summary: text)
            await persist()
        } catch {
            phase = .failed(message: error.localizedDescription)
            await persist()
        }
    }

    /// Explicit cancel only — hiding the panel must not call this.
    func cancelPendingPlan() {
        guard case .awaitingConfirmation = phase else { return }
        if let last = messages.last, last.role == .assistant, last.toolCalls != nil {
            mutateActive { $0.messages.removeLast() }
        }
        let text = "Cancelled. Nothing was changed."
        appendMessage(ChatMessage(role: .assistant, content: text))
        lastAssistantText = text
        mutateActive { $0.pendingPlan = nil }
        phase = .idle
        Task { await persist() }
    }

    func resetPhaseToIdle() {
        if case .completed = phase { phase = .idle }
        if case .failed = phase { phase = .idle }
    }

    // MARK: - Private

    private func handleTurn(_ turn: ModelTurn) async {
        if !turn.toolCalls.isEmpty {
            let summary = turn.content?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? "I can do this in \(turn.toolCalls.count) step\(turn.toolCalls.count == 1 ? "" : "s")."

            let storedCalls = turn.toolCalls.map {
                StoredToolCall(id: $0.id, name: $0.name, argumentsJSON: $0.argumentsJSON)
            }
            appendMessage(
                ChatMessage(
                    role: .assistant,
                    content: summary,
                    toolCalls: storedCalls
                )
            )

            let plan = AgentPlan(
                summary: summary,
                steps: turn.toolCalls.map { call in
                    AgentStep(
                        toolCallID: call.id,
                        toolName: call.name,
                        argumentsJSON: call.argumentsJSON,
                        title: humanTitle(for: call)
                    )
                }
            )
            mutateActive { $0.pendingPlan = plan }
            phase = .awaitingConfirmation(plan)
            await persist()
            return
        }

        let text = turn.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let reply = text.isEmpty ? "I couldn't produce a reply." : text
        appendMessage(ChatMessage(role: .assistant, content: reply))
        lastAssistantText = reply
        phase = .completed(summary: reply)
        await persist()
    }

    private func requestModel(includeTools: Bool = true) async throws -> ModelTurn {
        let snapshot = ModelSettingsSnapshot(
            baseURL: settings.baseURL,
            model: settings.model,
            apiKey: settings.apiKey
        )
        let skillsAppendix = capabilities?.skillsPromptAppendix() ?? ""
        var apiMessages = [ChatMessage(role: .system, content: systemPrompt + skillsAppendix)]
        apiMessages.append(contentsOf: messages)

        let toolDefs: [ToolDefinition]
        if includeTools {
            toolDefs = tools.definitions + (capabilities?.mcpToolDefinitions() ?? [])
        } else {
            toolDefs = []
        }

        return try await modelClient.complete(
            messages: apiMessages,
            tools: toolDefs,
            settings: snapshot
        )
    }

    private func ensureActiveSession() {
        if activeSessionID == nil || activeSession == nil {
            let session = ChatSession()
            sessions.insert(session, at: 0)
            activeSessionID = session.id
        }
    }

    private func appendMessage(_ message: ChatMessage) {
        mutateActive {
            $0.messages.append(message)
            $0.updatedAt = .now
        }
    }

    private func updateTitleIfNeeded(from userText: String) {
        mutateActive { session in
            if session.title == "New Chat" || session.messages.filter({ $0.role == .user }).count <= 1 {
                let trimmed = userText.trimmingCharacters(in: .whitespacesAndNewlines)
                session.title = String(trimmed.prefix(42))
            }
        }
    }

    private func mutateActive(_ body: (inout ChatSession) -> Void) {
        guard let id = activeSessionID,
              let index = sessions.firstIndex(where: { $0.id == id })
        else { return }
        body(&sessions[index])
        sessions.sort { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned && !rhs.isPinned }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    private func syncPhaseIntoActiveSession() {
        mutateActive { session in
            if case .awaitingConfirmation(let plan) = phase {
                session.pendingPlan = plan
            }
        }
    }

    private func restorePhaseFromActiveSession() {
        guard let session = activeSession else {
            phase = .idle
            lastAssistantText = nil
            return
        }
        lastAssistantText = session.messages.last(where: { $0.role == .assistant })?.content
        if let plan = session.pendingPlan {
            phase = .awaitingConfirmation(plan)
        } else {
            phase = .idle
        }
    }

    private func humanTitle(for call: ToolCallProposal) -> String {
        let args = (try? JSONDecoder().decode([String: JSONValue].self, from: Data(call.argumentsJSON.utf8))) ?? [:]
        switch call.name {
        case "list_directory":
            return "List \(args["path"]?.stringValue ?? "folder")"
        case "move_file":
            return "Move \(args["source"]?.stringValue ?? "file")"
        case "rename_file":
            return "Rename to \(args["new_name"]?.stringValue ?? "…")"
        case "create_directory":
            return "Create \(args["path"]?.stringValue ?? "folder")"
        case "read_text_file":
            return "Read \(args["path"]?.stringValue ?? "file")"
        case "write_text_file":
            return "Write \(args["path"]?.stringValue ?? "file")"
        case "get_clipboard":
            return "Read clipboard"
        case "set_clipboard":
            return "Update clipboard"
        case "open_application":
            return "Open \(args["name"]?.stringValue ?? "app")"
        case "open_url":
            return "Open URL"
        case "notify":
            return "Notify: \(args["title"]?.stringValue ?? "…")"
        default:
            return call.name
        }
    }

    private func persist() async {
        let snapshot = SessionLibrarySnapshot(
            sessions: sessions,
            activeSessionID: activeSessionID
        )
        await sessionStore.save(snapshot)
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
