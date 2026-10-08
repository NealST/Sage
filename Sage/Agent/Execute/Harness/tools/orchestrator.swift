//
//  orchestrator.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/orchestrator.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Approval → select sandbox → attempt → one escalate retry on denial.
//  Already-approved commands are not re-asked. `execute` owns validate,
//  timeout, and Sage dispatch; `ToolInvocationPipeline` only forwards.
//  `skipEventHooks` is set when `registry.dispatch` already ran Pre/Post.
//

import Foundation

@MainActor
struct ToolOrchestrator {
    var approvalStore: ApprovalStore

    init(approvalStore: ApprovalStore? = nil) {
        self.approvalStore = approvalStore ?? ApprovalStore()
    }

    @MainActor
    func run<Runtime: ToolRuntime>(
        tool: Runtime,
        request: Runtime.Request,
        ctx: ToolCtx,
        approver: any ApprovalRequesting
    ) async throws -> Runtime.Output {
        var alreadyApproved = false
        let fileSystem = ctx.fileSystemPolicy
        if ctx.allowUnsandboxedRetry, unsandboxedExecutionAllowed(fileSystem) {
            let cwd = tool.sandboxCwd(request) ?? ctx.workspaceRoot
            let attempt = SandboxAttempt.make(
                sandbox: .none,
                sandboxRequested: true,
                bits: permissionBits(from: request),
                cwd: cwd,
                ctx: ctx
            )
            return try await tool.run(request, attempt: attempt, ctx: ctx)
        }
        let requirement = tool.execApprovalRequirement(request)
            ?? defaultExecApprovalRequirement(ctx.approvalPolicy, fileSystem: fileSystem)

        switch requirement {
        case .skip:
            if Guardian.strictAutoReviewEnabled(policy: ctx.pathGuardPolicy) {
                try await requestApproval(
                    tool: tool,
                    request: request,
                    ctx: ctx,
                    approver: approver,
                    approvalReason: nil,
                    retryReason: nil
                )
                alreadyApproved = true
            }

        case .forbidden(let reason):
            throw HarnessToolError.rejected(reason)

        case .needsApproval(let reason):
            try await requestApproval(
                tool: tool,
                request: request,
                ctx: ctx,
                approver: approver,
                approvalReason: reason,
                retryReason: nil
            )
            alreadyApproved = true
        }

        let unsandboxedAllowed = unsandboxedExecutionAllowed(fileSystem)
        let sandboxOverride = if unsandboxedAllowed {
            sandboxOverrideForFirstAttempt(
                tool.sandboxPermissions(request),
                execApprovalRequirement: requirement,
                fileSystem: fileSystem
            )
        } else {
            SandboxOverride.noOverride
        }
        let (initialSandbox, sandboxRequested) = ExecSandbox.selectInitial(
            preference: tool.sandboxPreference(),
            override: sandboxOverride
        )
        let cwd = tool.sandboxCwd(request) ?? ctx.workspaceRoot
        let bits = permissionBits(from: request)
        let initialAttempt = SandboxAttempt.make(
            sandbox: initialSandbox,
            sandboxRequested: sandboxRequested,
            bits: bits,
            cwd: cwd,
            ctx: ctx
        )

        do {
            return try await tool.run(request, attempt: initialAttempt, ctx: ctx)
        } catch let error as HarnessToolError {
            guard case .sandboxDenied(let output) = error else {
                throw error
            }
            guard tool.escalateOnFailure() else {
                throw error
            }
            guard tool.wantsNoSandboxApproval(policy: ctx.approvalPolicy) else {
                throw error
            }
            // Codex stops when the sandbox cannot be dropped. Project mode is that case.
            guard unsandboxedAllowed else {
                throw error
            }

            let bypassRetryApproval = !Guardian.strictAutoReviewEnabled(policy: ctx.pathGuardPolicy)
                && tool.shouldBypassApproval(
                    policy: ctx.approvalPolicy,
                    alreadyApproved: alreadyApproved
                )
            if !bypassRetryApproval {
                if ctx.allowUnsandboxedRetry {
                    throw error
                }
                let approvalReason = if case .needsApproval(let reason) = requirement {
                    reason
                } else {
                    Optional<String>.none
                }
                do {
                    try await requestApproval(
                        tool: tool,
                        request: request,
                        ctx: ctx,
                        approver: approver,
                        approvalReason: approvalReason,
                        retryReason: NetworkApproval.retryReason(sandboxOutput: output)
                    )
                } catch {
                    throw error
                }
            }

            let retrySandbox = ExecSandbox.selectRetry(
                fileSystem: fileSystem,
                preference: tool.sandboxPreference()
            )
            let retryAttempt = SandboxAttempt.make(
                sandbox: retrySandbox,
                sandboxRequested: retrySandbox != .none,
                bits: bits,
                cwd: cwd,
                ctx: ctx
            )
            return try await tool.run(request, attempt: retryAttempt, ctx: ctx)
        }
    }

    /// Single execute entry. Validate, then shell/patch through the sandbox
    /// loop and every other tool through timed Sage dispatch.
    @MainActor
    static func execute(_ request: ToolInvocationRequest) async throws -> String {
        let prepared = try await prepare(request)
        let projectRoot = projectRoot(of: prepared.pathGuardPolicy)
        let activatedSkills = prepared.enabledSkills.filter { skill in
            prepared.activatedSkillNames.contains(skill.name)
        }
        if !prepared.skipEventHooks {
            let preTool = await HookRuntime.preToolUse(
                tool: prepared.name,
                command: prepared.argumentsJSON,
                projectRoot: projectRoot,
                argumentsJSON: prepared.argumentsJSON,
                activatedSkills: activatedSkills,
                sessionId: prepared.sessionId ?? "",
                turnId: prepared.turnId ?? "",
                cwd: projectRoot?.path,
                model: prepared.modelSettings?.model ?? "",
                permissionMode: "default",
                toolUseId: prepared.toolCallID
            )
            if preTool.shouldStop {
                throw HarnessToolError.rejected(preTool.additionalContexts.first ?? "Hook denied this tool.")
            }
        }
        let output: String
        if prepared.name == "run_shell_command" {
            output = try await executeShell(prepared)
        } else if prepared.name == "apply_patch" {
            output = try await ApplyPatchToolRuntime.execute(prepared)
        } else {
            output = try await dispatchTimed(prepared)
        }
        if !prepared.skipEventHooks {
            _ = await HookRuntime.postToolUse(
                tool: prepared.name,
                projectRoot: projectRoot,
                argumentsJSON: prepared.argumentsJSON,
                activatedSkills: activatedSkills,
                sessionId: prepared.sessionId ?? "",
                turnId: prepared.turnId ?? "",
                cwd: projectRoot?.path,
                model: prepared.modelSettings?.model ?? "",
                permissionMode: "default",
                toolUseId: prepared.toolCallID,
                toolResponse: output
            )
        }
        return output
    }

    /// Validate, hook, capability, observe. First hop of `execute`.
    @MainActor
    static func prepare(_ request: ToolInvocationRequest) async throws -> ToolInvocationRequest {
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
        return request
    }

    @MainActor
    static func dispatchTimed(_ request: ToolInvocationRequest) async throws -> String {
        try await withTimeout(name: request.name) {
            capToolResult(try await ToolInvocationDispatcher.dispatch(request))
        }
    }

    @MainActor
    static func withTimeout<T: Sendable>(
        name: String,
        operation: @escaping @MainActor () async throws -> T
    ) async throws -> T {
        let timeout = timeoutDuration(for: name)
        let work = Task { @MainActor in
            try await operation()
        }
        defer { work.cancel() }
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await work.value }
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

    nonisolated static func timeoutDuration(for name: String) -> Duration {
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

    private static func projectRoot(of policy: PathGuard.Policy) -> URL? {
        if case .project(let root) = policy { return root }
        return nil
    }

    @MainActor
    private static func executeShell(_ request: ToolInvocationRequest) async throws -> String {
        try await withTimeout(name: request.name) {
            let parsed = try ShellExecRequest.parse(
                request.argumentsJSON,
                policy: request.pathGuardPolicy
            )
            try ShellCommandPolicy.validate(parsed.command)
            if request.workPlanKind != .act, !parsed.permissionBits.isEmpty {
                throw ToolError.operationFailed(
                    """
                    Tool 'run_shell_command' would change the Mac, but this turn is \
                    not an act plan. Stick to observation tools, or wait for an act \
                    plan the user has confirmed.
                    """
                )
            }
            let ctx = ToolCtx.sage(request: request)
            let orchestrator = ToolOrchestrator(approvalStore: request.approvalStore)
            let output = try await orchestrator.run(
                tool: ShellRuntime(),
                request: parsed,
                ctx: ctx,
                approver: InvocationApprover(
                    authorization: request.authorization,
                    evidence: request.authorizationEvidence
                )
            )
            return capToolResult(output)
        }
    }

    @MainActor
    private func requestApproval<Runtime: ToolRuntime>(
        tool: Runtime,
        request: Runtime.Request,
        ctx: ToolCtx,
        approver: any ApprovalRequesting,
        approvalReason: String?,
        retryReason: String?
    ) async throws {
        let action = tool.approvalAction(request, callID: ctx.callID)
        let context = ApprovalContext(
            callID: ctx.callID,
            toolName: ctx.toolName,
            approvalReason: approvalReason,
            retryReason: retryReason
        )
        let permission = await HookRuntime.permissionRequest(
            tool: ctx.toolName,
            projectRoot: Self.projectRoot(of: ctx.pathGuardPolicy),
            argumentsJSON: ctx.argumentsJSON,
            sessionId: "",
            turnId: "",
            cwd: ctx.workspaceRoot.path,
            model: "",
            permissionMode: ctx.approvalPolicy == .never ? "bypassPermissions" : "default"
        )
        if permission.shouldStop {
            throw HarnessToolError.rejected(permission.additionalContexts.first ?? "Hook denied this approval.")
        }
        let decision = try await withCachedApproval(
            store: approvalStore,
            keys: [
                action.cacheKey,
                ApprovalStore.sessionCacheKey(
                    name: ctx.toolName,
                    argumentsJSON: ctx.argumentsJSON
                ),
            ]
        ) {
            let reviewed = await GuardianDecision.decide(
                action: action,
                context: context,
                options: GuardianReviewOptions(
                    requireGuardian: Guardian.requiresReview(
                        policy: ctx.pathGuardPolicy,
                        retry: retryReason != nil
                    )
                )
            )
            if let reviewed {
                return reviewed
            }
            return try await approver.requestApproval(action: action, context: context)
        }
        switch decision {
        case .approved, .approvedForSession:
            return

        case .denied(let reason):
            throw HarnessToolError.rejected(reason)

        case .abort:
            throw CancellationError()
        }
    }

    private func permissionBits<Request>(from request: Request) -> SandboxPermissionBits {
        (request as? ShellExecRequest)?.permissionBits ?? []
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
            HookRuntime.preToolUseDecision(
                tool: request.name,
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
