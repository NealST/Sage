//
//  AppState.swift
//  Sage
//

import SwiftUI

@Observable
@MainActor
final class AppState {
    var draft: String = ""
    var isAgentWindowVisible: Bool = false
    var hotkeyRegistrationFailed: Bool = false

    let settings: ModelSettings
    let capabilities: CapabilityStore
    let agent: AgentRuntime

    var statusHint: String {
        if hotkeyRegistrationFailed {
            return "Global shortcut unavailable"
        }
        if !settings.isConfigured {
            return "Set API key in Settings"
        }
        switch agent.phase {
        case .idle:
            return "Ask Sage to work on your Mac"
        case .thinking:
            return "Thinking…"
        case .awaitingConfirmation:
            return "Plan waiting for confirmation"
        case .executing:
            return "Working…"
        case .completed:
            return "Done"
        case .failed(let message):
            return Self.compactStatus(message)
        }
    }

    var isConfigurationFailure: Bool {
        guard case .failed(let message) = agent.phase else { return false }
        return Self.looksLikeConfigurationError(message, isConfigured: settings.isConfigured)
    }

    convenience init() {
        self.init(settings: .shared)
    }

    init(settings: ModelSettings) {
        self.settings = settings
        let capabilities = CapabilityStore()
        self.capabilities = capabilities
        self.agent = AgentRuntime(
            settings: settings,
            tools: .makeDefault(),
            taskRepository: GRDBTaskRepository(),
            contextResolver: ContinuityTaskResolver(),
            capabilities: capabilities
        )
    }

    func clearDraft() {
        draft = ""
    }

    @discardableResult
    func eraseAllLocalData() async -> Bool {
        clearDraft()
        return await agent.eraseAllData()
    }

    static func looksLikeConfigurationError(_ message: String, isConfigured: Bool) -> Bool {
        let lower = message.lowercased()
        return !isConfigured
            || lower.contains("api key")
            || lower.contains("settings")
            || lower.contains("base url")
            || lower.contains("not configured")
            || lower.contains("401")
            || lower.contains("403")
    }

    private static func compactStatus(_ message: String) -> String {
        let trimmed = message
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 48 { return trimmed }
        return String(trimmed.prefix(45)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }
}
