import Foundation

/// Single dispatch surface for built-in, skill, and MCP tools.
/// File and shell tools hop off the main actor. AppKit / Accessibility tools stay on it.
/// Skill and MCP hop back because their hosts are main-actor isolated.
nonisolated enum ToolInvocationDispatcher {
    @MainActor
    static func execute(_ request: ToolInvocationRequest) async throws -> String {
        try await ToolInvocationPipeline.execute(request)
    }

    /// Dispatches an invocation after `ToolInvocationPipeline` applies policy and schema checks.
    @MainActor
    static func dispatch(_ request: ToolInvocationRequest) async throws -> String {
        if let result = try await dispatchSpecializedTool(request) {
            return result
        }

        guard let tool = request.tools.tool(named: request.name) else {
            throw ToolError.operationFailed("Unknown tool: \(request.name)")
        }

        let allowlist = SkillToolExecutor.readAllowlist(
            activatedSkillNames: request.activatedSkillNames,
            enabledSkills: request.enabledSkills
        ) + request.extraReadAllowlist
        let authorization = ToolAuthorizationPolicy.requirement(
            name: request.name,
            argumentsJSON: request.argumentsJSON,
            policy: request.pathGuardPolicy,
            skills: request.authorizationSkills ?? request.enabledSkills,
            mcpTools: request.mcp?.mcpTools ?? []
        )

        return try await Self.invokeBuiltIn(
            named: request.name,
            tool: tool,
            argumentsJSON: request.argumentsJSON,
            pathGuardPolicy: request.pathGuardPolicy,
            allowlist: allowlist,
            sensitiveReadRoots: authorization?.roots(for: .sensitiveRead) ?? [],
            writeRoots: authorization?.roots(for: .localWrite) ?? []
        )
    }

    @MainActor
    static func dispatchSpecializedTool(_ request: ToolInvocationRequest) async throws -> String? {
        if request.name == RecallTaskTranscriptTool.name {
            return try await RecallTaskTranscriptTool.execute(argumentsJSON: request.argumentsJSON)
        }
        if request.name == ManageTodoListTool.name {
            return try await ManageTodoListTool.execute(argumentsJSON: request.argumentsJSON)
        }
        if request.name == ExploreSubagentTool.name {
            guard let modelSettings = request.modelSettings else {
                throw ToolError.operationFailed("Explore subagent model settings are unavailable.")
            }
            return try await ExploreSubagentRunner.run(
                argumentsJSON: request.argumentsJSON,
                settings: modelSettings,
                tools: request.tools,
                pathGuardPolicy: request.pathGuardPolicy,
                skillHost: request.skillHost,
                extraReadAllowlist: request.extraReadAllowlist
            )
        }
        if MCPToolGroupTool.isGroupTool(request.name) {
            return try await MCPToolGroupTool.execute(
                name: request.name,
                availableTools: request.mcp?.mcpToolDefinitions() ?? []
            )
        }
        if request.name.hasPrefix("mcp__") {
            guard let mcp = request.mcp else {
                throw ToolError.operationFailed("MCP tools are unavailable.")
            }
            return try await mcp.callMCPTool(
                qualifiedName: request.name,
                argumentsJSON: request.argumentsJSON,
                temporaryWriteRoots: request.mcpWriteRoots,
                allowsProtectedMetadataWrites: request.mcpAllowsProtectedMetadataWrites
            )
        }
        if SkillToolExecutor.isSkillTool(request.name) {
            return try await SkillToolExecutor.execute(
                name: request.name,
                argumentsJSON: request.argumentsJSON,
                host: request.skillHost
            )
        }
        return nil
    }

    /// Rejects tools that change the Mac unless the work plan is `act`.
    ///
    /// Answer / observe turns skip plan confirmation, so this is the runtime
    /// backstop. A missing plan is treated as non-act.
    static func assertMutatingToolsAllowed(
        for name: String,
        workPlanKind: WorkPlan.Kind?,
        requiresConfirmation: Bool? = nil
    ) throws {
        guard workPlanKind != .act else { return }
        let requiresConfirmation = requiresConfirmation
            ?? ToolDefinition.requiresConfirmation(forToolNamed: name)
        guard requiresConfirmation else { return }
        let planLabel = switch workPlanKind {
        case .observe:
            "an observe plan (read/list/search only)"

        case .answer:
            "an answer plan (no Mac changes)"

        case .act, nil:
            "not an act plan"
        }
        throw ToolError.operationFailed(
            """
            Tool '\(name)' would change the Mac, but this turn is \(planLabel). \
            Stick to observation tools, or wait for an act plan the user has confirmed.
            """
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
        allowlist: [String],
        sensitiveReadRoots: [String],
        writeRoots: [String]
    ) async throws -> String {
        if mainActorToolNames.contains(name) {
            return try await PathGuard.$policy.withValue(pathGuardPolicy) {
                try await PathGuard.$readAllowlist.withValue(allowlist) {
                    try await PathGuard.$sensitiveReadAllowlist.withValue(sensitiveReadRoots) {
                        try await PathGuard.$writeAllowlist.withValue(writeRoots) {
                            try await tool.call(argumentsJSON: argumentsJSON)
                        }
                    }
                }
            }
        }
        return try await Task.detached(priority: .userInitiated) {
            try await PathGuard.$policy.withValue(pathGuardPolicy) {
                try await PathGuard.$readAllowlist.withValue(allowlist) {
                    try await PathGuard.$sensitiveReadAllowlist.withValue(sensitiveReadRoots) {
                        try await PathGuard.$writeAllowlist.withValue(writeRoots) {
                            try await tool.call(argumentsJSON: argumentsJSON)
                        }
                    }
                }
            }
        }.value
    }
}
