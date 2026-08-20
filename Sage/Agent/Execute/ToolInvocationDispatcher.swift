import Foundation

/// Single dispatch surface for built-in, skill, and MCP tools.
/// File and shell tools hop off the main actor. AppKit / Accessibility tools stay on it.
/// Skill and MCP hop back because their hosts are main-actor isolated.
nonisolated enum ToolInvocationDispatcher {
    @MainActor
    static func execute(
        name: String,
        argumentsJSON: String,
        tools: ToolRegistry,
        mcp: CapabilityStore?,
        pathGuardPolicy: PathGuard.Policy,
        activatedSkillNames: Set<String>,
        enabledSkills: [SkillRecord],
        skillHost: SkillToolHost,
        workPlanKind: WorkPlan.Kind? = nil,
        modelSettings: ModelSettingsSnapshot? = nil
    ) async throws -> String {
        try await ToolInvocationPipeline.execute(
            name: name,
            argumentsJSON: argumentsJSON,
            tools: tools,
            mcp: mcp,
            pathGuardPolicy: pathGuardPolicy,
            activatedSkillNames: activatedSkillNames,
            enabledSkills: enabledSkills,
            skillHost: skillHost,
            workPlanKind: workPlanKind,
            modelSettings: modelSettings
        )
    }

    /// Dispatches an invocation after `ToolInvocationPipeline` applies policy and schema checks.
    @MainActor
    static func dispatch(
        name: String,
        argumentsJSON: String,
        tools: ToolRegistry,
        mcp: CapabilityStore?,
        pathGuardPolicy: PathGuard.Policy,
        activatedSkillNames: Set<String>,
        enabledSkills: [SkillRecord],
        skillHost: SkillToolHost,
        modelSettings: ModelSettingsSnapshot?
    ) async throws -> String {
        if name == RecallTaskTranscriptTool.name {
            return try await RecallTaskTranscriptTool.execute(argumentsJSON: argumentsJSON)
        }
        if name == ManageTodoListTool.name {
            return try await ManageTodoListTool.execute(argumentsJSON: argumentsJSON)
        }
        if name == ExploreSubagentTool.name {
            guard let modelSettings else {
                throw ToolError.operationFailed("Explore subagent model settings are unavailable.")
            }
            return try await ExploreSubagentRunner.run(
                argumentsJSON: argumentsJSON,
                settings: modelSettings,
                tools: tools,
                pathGuardPolicy: pathGuardPolicy,
                skillHost: skillHost
            )
        }
        if MCPToolGroupTool.isGroupTool(name) {
            return try await MCPToolGroupTool.execute(
                name: name,
                availableTools: mcp?.mcpToolDefinitions() ?? []
            )
        }

        if name.hasPrefix("mcp__") {
            guard let mcp else {
                throw ToolError.operationFailed("MCP tools are unavailable.")
            }
            return try await mcp.callMCPTool(qualifiedName: name, argumentsJSON: argumentsJSON)
        }

        if SkillToolExecutor.isSkillTool(name) {
            return try await SkillToolExecutor.execute(
                name: name,
                argumentsJSON: argumentsJSON,
                host: skillHost
            )
        }

        guard let tool = tools.tool(named: name) else {
            throw ToolError.operationFailed("Unknown tool: \(name)")
        }

        let allowlist = SkillToolExecutor.readAllowlist(
            activatedSkillNames: activatedSkillNames,
            enabledSkills: enabledSkills
        )

        return try await Self.invokeBuiltIn(
            named: name,
            tool: tool,
            argumentsJSON: argumentsJSON,
            pathGuardPolicy: pathGuardPolicy,
            allowlist: allowlist
        )
    }

    /// Rejects tools that change the Mac unless the work plan is `act`.
    ///
    /// Answer / observe turns skip plan confirmation, so this is the runtime
    /// backstop. A missing plan is treated as non-act.
    static func assertMutatingToolsAllowed(
        for name: String,
        workPlanKind: WorkPlan.Kind?
    ) throws {
        guard workPlanKind != .act else { return }
        guard ToolDefinition.requiresConfirmation(forToolNamed: name) else { return }
        let planLabel = switch workPlanKind {
        case .observe:
            "an observe plan (read/list/search only)"

        case .answer:
            "an answer plan (no Mac changes)"

        case .act, nil:
            "not an act plan"
        }
        throw ToolError.operationFailed(
            "Tool '\(name)' would change the Mac, but this turn is \(planLabel). Stick to observation tools, or wait for an act plan the user has confirmed."
        )
    }

    /// Pasteboard, Accessibility, and windowing APIs must run on the main actor.
    private static let mainActorToolNames: Set<String> = [
        "get_clipboard",
        "set_clipboard",
        "get_selected_text",
        "type_text",
        "get_frontmost_app",
        "get_screen_info",
        "toggle_appearance",
        "open_url",
        "open_application",
        "notify",
        "take_screenshot",
    ]

    @MainActor
    private static func invokeBuiltIn(
        named name: String,
        tool: any AgentTool,
        argumentsJSON: String,
        pathGuardPolicy: PathGuard.Policy,
        allowlist: [String]
    ) async throws -> String {
        if mainActorToolNames.contains(name) {
            return try await PathGuard.$policy.withValue(pathGuardPolicy) {
                try await PathGuard.$readAllowlist.withValue(allowlist) {
                    try await tool.call(argumentsJSON: argumentsJSON)
                }
            }
        }
        return try await Task.detached(priority: .userInitiated) {
            try await PathGuard.$policy.withValue(pathGuardPolicy) {
                try await PathGuard.$readAllowlist.withValue(allowlist) {
                    try await tool.call(argumentsJSON: argumentsJSON)
                }
            }
        }.value
    }
}
