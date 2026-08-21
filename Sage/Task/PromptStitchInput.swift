//
//  PromptStitchInput.swift
//  Sage
//

import Foundation

nonisolated struct PromptStitchInput: Sendable {
    var system: String
    var user: AgentEvent?
    var latest: [AgentEvent]
    var protected: [AgentEvent]
    var history: [AgentEvent]
    var prefixOrder: [AgentEvent]
}
