import Foundation

/// Single dispatch surface for built-in, skill, and MCP tools.
/// Built-in file/shell tools run off the main actor. Skill and MCP hop back
/// because their hosts are main-actor isolated.
nonisolated enum ToolInvocationDispatcher {
    private static let interactiveTools: Set<String> = [
        "run_shell_command",
        "take_screenshot",
        "toggle_appearance",
        "create_reminder",
    ]

    static func execute(
        name: String,
        argumentsJSON: String,
        tools: ToolRegistry,
        mcp: CapabilityStore?,
        pathGuardPolicy: PathGuard.Policy,
        activatedSkillNames: Set<String>,
        enabledSkills: [SkillRecord],
        skillHost: SkillToolHost
    ) async throws -> String {
        try SkillToolPolicy.assertToolAllowed(
            name,
            activatedSkillNames: activatedSkillNames,
            enabledSkills: enabledSkills
        )

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

        let timeout: Duration = interactiveTools.contains(name)
            ? .seconds(130)
            : toolExecutionTimeout
        let allowlist = SkillToolExecutor.readAllowlist(
            activatedSkillNames: activatedSkillNames,
            enabledSkills: enabledSkills
        )

        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await PathGuard.$policy.withValue(pathGuardPolicy) {
                    try await PathGuard.$readAllowlist.withValue(allowlist) {
                        try await tool.call(argumentsJSON: argumentsJSON)
                    }
                }
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw ToolError.operationFailed(
                    "Tool '\(name)' timed out after \(Int(timeout.components.seconds))s"
                )
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}
