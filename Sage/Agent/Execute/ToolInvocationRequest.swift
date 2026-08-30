//
//  ToolInvocationRequest.swift
//  Sage
//
//  Shared inputs for policy, validation, and dispatch of one tool call.
//

import Foundation

nonisolated struct ToolInvocationAuthorizationEvidence: Sendable, Equatable {
    var requirementKey: String
}

nonisolated struct ToolInvocationHookEvidence: Sendable, Equatable {
    var invocationKey: String
}

struct ToolInvocationRequest {
    var name: String
    var argumentsJSON: String
    var tools: ToolRegistry
    var mcp: CapabilityStore?
    var pathGuardPolicy: PathGuard.Policy
    var activatedSkillNames: Set<String>
    var enabledSkills: [SkillRecord]
    var authorizationSkills: [SkillRecord]?
    var skillHost: SkillToolHost
    var workPlanKind: WorkPlan.Kind?
    var modelSettings: ModelSettingsSnapshot?
    /// Precomputed requirement. Set via `resolvingAuthorization()` so policy is not re-derived.
    var authorization: ToolAuthorizationRequirement?
    var didResolveAuthorization = false
    /// Proof that the session consumed or matched a capability grant for this exact requirement.
    var authorizationEvidence: ToolInvocationAuthorizationEvidence?
    /// When set, the pipeline skips a second PreToolUse evaluation.
    var hookDecision: PreToolUseDecision?
    /// Proof that an exact invocation was approved after a PreToolUse hook returned `.ask`.
    var hookEvidence: ToolInvocationHookEvidence?
    /// Temporary write roots granted for this MCP invocation.
    var mcpWriteRoots: [URL] = []
    /// Whether this MCP invocation may write protected project metadata.
    var mcpAllowsProtectedMetadataWrites = false
    /// Extra read-only paths (user attachments). Merged with skill dirs at dispatch.
    var extraReadAllowlist: [String] = []

    func resolvingAuthorization() -> Self {
        guard !didResolveAuthorization else { return self }
        var copy = self
        copy.authorization = ToolAuthorizationPolicy.requirement(
            name: name,
            argumentsJSON: argumentsJSON,
            policy: pathGuardPolicy,
            skills: authorizationSkills ?? enabledSkills,
            mcpTools: mcp?.mcpTools ?? []
        )
        copy.didResolveAuthorization = true
        return copy
    }
}
