//
//  AppState.swift
//  Sage
//

import SwiftUI

@Observable
@MainActor
final class AppState {
    var draft: String = ""
    var isHUDVisible: Bool = false

    let settings: ModelSettings
    let capabilities: CapabilityStore
    let agent: AgentRuntime

    var statusHint: String {
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
            return message
        }
    }

    init(settings: ModelSettings = .shared) {
        self.settings = settings
        let capabilities = CapabilityStore()
        self.capabilities = capabilities
        self.agent = AgentRuntime(settings: settings, capabilities: capabilities)
    }

    func clearDraft() {
        draft = ""
    }
}
