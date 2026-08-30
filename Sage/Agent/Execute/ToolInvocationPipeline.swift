//
//  ToolInvocationPipeline.swift
//  Sage
//
//  One policy / validation / dispatch surface for every tool invocation.
//

import Foundation

nonisolated enum ToolInvocationPipeline {
    @MainActor
    static func execute(_ request: ToolInvocationRequest) async throws -> String {
        let request = request.resolvingAuthorization()
        let definition = try validateForAuthorization(request)
        try await assertHookAuthorized(request)
        try assertCapabilityAuthorized(request)
        let writesLocally = request.authorization?.capabilities.contains { capability in
            capability == .localWrite || capability == .protectedMetadataWrite
        } == true
        try ToolInvocationDispatcher.assertMutatingToolsAllowed(
            for: request.name,
            workPlanKind: request.workPlanKind,
            requiresConfirmation: definition.requiresConfirmation || writesLocally
        )

        let timeout = timeoutDuration(for: request.name)
        let operation = Task { @MainActor in
            try await ToolInvocationDispatcher.dispatch(request)
        }
        defer { operation.cancel() }
        let result = try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask { try await operation.value }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw ToolError.operationFailed(
                    "Tool '\(request.name)' timed out after \(Int(timeout.components.seconds))s"
                )
            }
            guard let result = try await group.next() else {
                throw ToolError.operationFailed("Tool '\(request.name)' produced no result.")
            }
            group.cancelAll()
            return result
        }
        return capToolResult(result)
    }

    @MainActor
    static func validateForAuthorization(
        _ request: ToolInvocationRequest
    ) throws -> ToolDefinition {
        let request = request.resolvingAuthorization()
        try SkillToolPolicy.assertToolAllowed(
            request.name,
            activatedSkillNames: request.activatedSkillNames,
            enabledSkills: request.enabledSkills
        )

        let definition = try definition(
            for: request.name,
            tools: request.tools,
            mcp: request.mcp
        )
        try ToolArgumentValidator.validate(
            argumentsJSON: request.argumentsJSON,
            against: definition.parameters
        )
        if let validationError = request.authorization?.validationError {
            throw ToolError.invalidArguments(validationError)
        }
        return definition
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
    private static func assertHookAuthorized(
        _ request: ToolInvocationRequest
    ) async throws {
        let projectRoot: URL? = if case .project(let root) = request.pathGuardPolicy {
            root
        } else {
            nil
        }
        let activatedSkills = request.enabledSkills.filter { skill in
            request.activatedSkillNames.contains(skill.name)
        }
        let decision = if let hookDecision = request.hookDecision {
            hookDecision
        } else {
            await PreToolUseHookEvaluator.shared.evaluate(
                toolName: request.name,
                argumentsJSON: request.argumentsJSON,
                projectRoot: projectRoot,
                activatedSkills: activatedSkills
            )
        }
        switch decision {
        case .allow:
            return

        case .deny(let reason):
            throw ToolError.operationFailed("Blocked by PreToolUse hook: \(reason)")

        case .ask(let approval):
            let key = SessionToolAllowlist.hookApprovalKey(
                name: request.name,
                argumentsJSON: request.argumentsJSON,
                hookIdentity: approval.identity
            )
            guard request.hookEvidence?.invocationKey == key else {
                throw ToolError.operationFailed(
                    "PreToolUse hook requires interactive approval: \(approval.reason)"
                )
            }
        }
    }

    @MainActor
    private static func assertCapabilityAuthorized(
        _ request: ToolInvocationRequest
    ) throws {
        guard let requirement = request.resolvingAuthorization().authorization else { return }
        guard request.authorizationEvidence?.requirementKey == requirement.stableKey else {
            throw ToolError.operationFailed("This tool call requires authorization.")
        }
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
