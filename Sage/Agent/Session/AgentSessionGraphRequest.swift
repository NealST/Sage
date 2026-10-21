//
//  AgentSessionGraphRequest.swift
//  Sage
//

import Foundation

@MainActor
struct AgentSessionGraphRequest {
    var settings: ModelSettings
    var tools: ToolRegistry
    var taskRepository: any TaskRepository
    var contextResolver: any TaskRouting
    var skillCatalog: SkillCatalog?
    var mcpHub: CapabilityStore?
    var skills: SkillSessionController
    var systemPrompt: String
    var streaming: StreamingTextPump
    var streamingPlayback: StreamingPlayback
}
