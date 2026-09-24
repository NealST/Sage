//
//  orchestrator.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/orchestrator.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Approval → select sandbox → attempt → one escalate retry on denial.
//  Already-approved commands are not re-asked. `ToolInvocationPipeline`
//  is the validate / timeout / dispatch hop inside `execute`.
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

    /// Single execute entry. Pipeline validates; shell takes the sandbox loop;
    /// every other tool is the timed dispatch hop.
    @MainActor
    static func execute(_ request: ToolInvocationRequest) async throws -> String {
        let prepared = try await ToolInvocationPipeline.prepare(request)
        let projectRoot = projectRoot(of: prepared.pathGuardPolicy)
        let preTool = HookRuntime.preToolUse(
            tool: prepared.name,
            command: prepared.argumentsJSON,
            projectRoot: projectRoot
        )
        if preTool.shouldStop {
            throw HarnessToolError.rejected(preTool.additionalContexts.first ?? "Hook denied this tool.")
        }
        let output: String
        if prepared.name == "run_shell_command" {
            output = try await executeShell(prepared)
        } else if prepared.name == "apply_patch" {
            output = try await ApplyPatchToolRuntime.execute(prepared)
        } else {
            output = try await ToolInvocationPipeline.dispatchTimed(prepared)
        }
        _ = HookRuntime.postToolUse(tool: prepared.name, projectRoot: projectRoot)
        return output
    }

    private static func projectRoot(of policy: PathGuard.Policy) -> URL? {
        if case .project(let root) = policy { return root }
        return nil
    }

    @MainActor
    private static func executeShell(_ request: ToolInvocationRequest) async throws -> String {
        try await ToolInvocationPipeline.withTimeout(name: request.name) {
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
            let orchestrator = ToolOrchestrator()
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
        let permission = HookRuntime.permissionRequest(tool: ctx.toolName, projectRoot: projectRoot(of: ctx.pathGuardPolicy))
        if permission.shouldStop {
            throw HarnessToolError.rejected(permission.additionalContexts.first ?? "Hook denied this approval.")
        }
        let decision = try await withCachedApproval(
            store: approvalStore,
            keys: [action.cacheKey]
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
}
