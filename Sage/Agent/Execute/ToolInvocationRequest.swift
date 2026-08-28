//
//  ToolInvocationRequest.swift
//  Sage
//
//  Shared inputs for policy, validation, and dispatch of one tool call.
//

import Foundation

struct ToolInvocationRequest {
    var name: String
    var argumentsJSON: String
    var tools: ToolRegistry
    var mcp: CapabilityStore?
    var pathGuardPolicy: PathGuard.Policy
    var activatedSkillNames: Set<String>
    var enabledSkills: [SkillRecord]
    var skillHost: SkillToolHost
    var workPlanKind: WorkPlan.Kind?
    var modelSettings: ModelSettingsSnapshot?
    /// Temporary write roots granted for this MCP invocation.
    var mcpWriteRoots: [URL] = []
    /// Extra read-only paths (user attachments). Merged with skill dirs at dispatch.
    var extraReadAllowlist: [String] = []
}
