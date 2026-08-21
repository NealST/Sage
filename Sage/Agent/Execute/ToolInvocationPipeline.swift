//
//  ToolInvocationPipeline.swift
//  Sage
//
//  One policy / validation / dispatch surface for every tool invocation.
//

import Foundation

nonisolated enum ToolInvocationPipeline {
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
        workPlanKind: WorkPlan.Kind?,
        modelSettings: ModelSettingsSnapshot?
    ) async throws -> String {
        try ToolInvocationDispatcher.assertMutatingToolsAllowed(
            for: name,
            workPlanKind: workPlanKind
        )
        try SkillToolPolicy.assertToolAllowed(
            name,
            activatedSkillNames: activatedSkillNames,
            enabledSkills: enabledSkills
        )

        let definition = try definition(for: name, tools: tools, mcp: mcp)
        try ToolArgumentValidator.validate(
            argumentsJSON: argumentsJSON,
            against: definition.parameters
        )

        let timeout = timeoutDuration(for: name)
        let operation = Task { @MainActor in
            try await ToolInvocationDispatcher.dispatch(
                name: name,
                argumentsJSON: argumentsJSON,
                tools: tools,
                mcp: mcp,
                pathGuardPolicy: pathGuardPolicy,
                activatedSkillNames: activatedSkillNames,
                enabledSkills: enabledSkills,
                skillHost: skillHost,
                modelSettings: modelSettings
            )
        }
        defer { operation.cancel() }
        let result = try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask { try await operation.value }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw ToolError.operationFailed(
                    "Tool '\(name)' timed out after \(Int(timeout.components.seconds))s"
                )
            }
            guard let result = try await group.next() else {
                throw ToolError.operationFailed("Tool '\(name)' produced no result.")
            }
            group.cancelAll()
            return result
        }
        return capToolResult(result)
    }

    static func timeoutDuration(for name: String) -> Duration {
        if name.hasPrefix("mcp__")
            || name == ExploreSubagentTool.name
            || name == "run_shell_command"
            || name == "take_screenshot"
            || name == "toggle_appearance"
            || name == "create_reminder"
            || name == SkillToolExecutor.runSkillScriptDefinition.name {
            return .seconds(130)
        }
        return toolExecutionTimeout
    }

    @MainActor
    private static func definition(
        for name: String,
        tools: ToolRegistry,
        mcp: CapabilityStore?
    ) throws -> ToolDefinition {
        if name == RecallTaskTranscriptTool.name {
            return RecallTaskTranscriptTool.definition
        }
        if name == ManageTodoListTool.name {
            return ManageTodoListTool.definition
        }
        if name == ExploreSubagentTool.name {
            return ExploreSubagentTool.definition
        }
        if let server = MCPToolGroupTool.serverName(fromGroupTool: name) {
            let definitions = mcp?.mcpToolDefinitions().filter { definition in
                MCPToolGroupTool.serverName(fromQualifiedTool: definition.name) == server
            } ?? []
            guard !definitions.isEmpty else {
                throw ToolError.operationFailed("MCP server '\(server)' has no available tools.")
            }
            return MCPToolGroupTool.groupDefinition(server: server, tools: definitions)
        }
        if name.hasPrefix("mcp__"),
           let definition = mcp?.mcpToolDefinitions().first(where: { $0.name == name }) {
            return definition
        }
        if let definition = skillDefinition(named: name) {
            return definition
        }
        if let definition = tools.tool(named: name)?.definition {
            return definition
        }
        throw ToolError.operationFailed("Unknown tool: \(name)")
    }

    private static func skillDefinition(named name: String) -> ToolDefinition? {
        switch name {
        case SkillToolExecutor.loadSkillDefinition.name:
            return SkillToolExecutor.loadSkillDefinition

        case SkillToolExecutor.loadSkillResourceDefinition.name:
            return SkillToolExecutor.loadSkillResourceDefinition

        case SkillToolExecutor.runSkillScriptDefinition.name:
            return SkillToolExecutor.runSkillScriptDefinition

        case SkillToolExecutor.saveSkillDefinition.name:
            return SkillToolExecutor.saveSkillDefinition

        default:
            return nil
        }
    }
}
