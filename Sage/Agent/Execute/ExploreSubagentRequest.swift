//
//  ExploreSubagentRequest.swift
//  Sage
//

import Foundation

@MainActor
struct ExploreSubagentRequest {
    var task: String
    var context: String?
    var instructions: String?
    var settings: ModelSettingsSnapshot
    var tools: ToolRegistry
    var pathGuardPolicy: PathGuard.Policy
    var skillHost: SkillToolHost
    var activatedSkillNames: Set<String>
    var enabledSkills: [SkillRecord]
    var extraReadAllowlist: [String] = []
}
