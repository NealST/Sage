//
//  ExecuteServices.swift
//  Sage
//
//  Dependency bag for ToolBatchExecutor.
//

import Foundation

@MainActor
struct ExecuteServices {
    let state: AgentSessionState
    let planProgress: PlanProgress
    let taskStore: AgentTaskStore
    let modelGateway: AgentModelGateway
    let modelSettings: () -> ModelSettingsSnapshot
    let tools: ToolRegistry
    let mcp: CapabilityStore?
    let skillHost: SkillToolHost
    let topicCoordinator: TopicCoordinator
    let clearStream: () -> Void
    /// After a batch finishes, offer tools again (ReAct) unless the loop cap is hit.
    let allowToolsAfterExecute: () -> Bool
    let continueTurn: (ModelTurn) async -> Void
    let preToolUseDecision: (String, String) async -> PreToolUseDecision
    let isToolApproved: (String, String) -> Bool
    let isHookApproved: (String, String, String) -> Bool
    let pauseForToolApproval: (AgentStep) async -> Void
    let pauseForToolRoundLimit: () async -> Void

    var events: [AgentEvent] { state.events }

    func activateSkill(named name: String) {
        state.activatedSkillNames.insert(name)
    }

    func commit(
        appendEvents: [AgentEvent],
        deleteEventIDs: [UUID],
        mutate: (inout TaskRecord) -> Void = { _ in }
    ) async -> Bool {
        await taskStore.commit(
            appendEvents: appendEvents,
            deleteEventIDs: deleteEventIDs,
            mutate: mutate
        )
    }

    func persistPlanStepStatus(_ step: AgentStep, in plan: AgentPlan) async -> Bool {
        await taskStore.persistPlanStepStatus(step, in: plan)
    }

    func executeToolInvocation(name: String, argumentsJSON: String) async throws -> String {
        let request = try await preparedInvocation(name: name, argumentsJSON: argumentsJSON)
        return try await taskStore.withActiveTaskContext {
            try await ToolInvocationDispatcher.execute(request)
        }
    }

    private func preparedInvocation(
        name: String,
        argumentsJSON: String
    ) async throws -> ToolInvocationRequest {
        let hookDecision = await evaluatePreToolUse(name: name, argumentsJSON: argumentsJSON)
        let hookEvidence = try consumeHookEvidence(
            hookDecision,
            name: name,
            argumentsJSON: argumentsJSON
        )
        let authorization = try authorizationForInvocation(
            name: name,
            argumentsJSON: argumentsJSON
        )
        let mcpWriteRoots = authorization.requirement?.principal.hasPrefix("mcp:") == true
            ? authorization.requirement?.roots(for: .localWrite).map { root in
                URL(fileURLWithPath: root, isDirectory: true)
            } ?? []
            : []
        return invocationRequest(
            name: name,
            argumentsJSON: argumentsJSON,
            authorization: authorization.requirement,
            authorizationEvidence: authorization.evidence,
            hookDecision: hookDecision,
            hookEvidence: hookEvidence,
            mcpWriteRoots: mcpWriteRoots,
            mcpAllowsProtectedMetadataWrites: authorization.requirement?
                .capabilities.contains(.protectedMetadataWrite) == true
        )
    }

    private func consumeHookEvidence(
        _ hookDecision: PreToolUseDecision,
        name: String,
        argumentsJSON: String
    ) throws -> ToolInvocationHookEvidence? {
        switch hookDecision {
        case .allow:
            return nil

        case .deny(let reason):
            throw ToolError.operationFailed("Blocked by PreToolUse hook: \(reason)")

        case .ask(let approval):
            guard state.sessionAllowlist.containsHookApproval(
                name: name,
                argumentsJSON: argumentsJSON,
                hookIdentity: approval.identity,
                scopeID: state.authorizationScopeID
            ) else {
                throw ToolError.operationFailed(
                    "PreToolUse hook requires interactive approval: \(approval.reason)"
                )
            }
            guard state.sessionAllowlist.consumeHookApproval(
                name: name,
                argumentsJSON: argumentsJSON,
                hookIdentity: approval.identity,
                scopeID: state.authorizationScopeID
            ) else {
                throw ToolError.operationFailed("The safety hook approval is no longer available.")
            }
            return ToolInvocationHookEvidence(
                invocationKey: SessionToolAllowlist.hookApprovalKey(
                    name: name,
                    argumentsJSON: argumentsJSON,
                    hookIdentity: approval.identity
                )
            )
        }
    }

    private func authorizationForInvocation(
        name: String,
        argumentsJSON: String
    ) throws -> (
        requirement: ToolAuthorizationRequirement?,
        evidence: ToolInvocationAuthorizationEvidence?
    ) {
        let requirement = ToolAuthorizationPolicy.requirement(
            name: name,
            argumentsJSON: argumentsJSON,
            policy: state.pathGuardPolicy,
            skills: skillHost.catalogSkills,
            mcpTools: mcp?.mcpTools ?? []
        )
        guard let requirement else { return (nil, nil) }
        guard state.sessionAllowlist.consumeApproval(
            requirement,
            name: name,
            argumentsJSON: argumentsJSON,
            scopeID: state.authorizationScopeID
        ) else {
            throw ToolError.operationFailed("This tool call requires authorization.")
        }
        return (
            requirement,
            ToolInvocationAuthorizationEvidence(requirementKey: requirement.stableKey)
        )
    }

    func validateToolInvocation(name: String, argumentsJSON: String) throws {
        _ = try ToolInvocationPipeline.validateForAuthorization(
            invocationRequest(name: name, argumentsJSON: argumentsJSON)
        )
    }

    func evaluatePreToolUse(name: String, argumentsJSON: String) async -> PreToolUseDecision {
        await preToolUseDecision(name, argumentsJSON)
    }

    func requiresAuthorization(name: String, argumentsJSON: String) -> Bool {
        SessionToolAllowlist.needsGate(
            name: name,
            argumentsJSON: argumentsJSON,
            policy: state.pathGuardPolicy,
            skills: skillHost.enabledSkills,
            mcpTools: mcp?.mcpTools ?? []
        )
    }

    func loadSkillName(from argumentsJSON: String) -> String? {
        SkillToolExecutor.loadSkillName(from: argumentsJSON)
    }

    func requestModelStreaming(includeTools: Bool) async throws -> ModelTurn {
        try await modelGateway.streamComplete(includeTools: includeTools)
    }

    func generateTopicIfNeeded() {
        topicCoordinator.generateTopicIfNeeded(for: state.activeTask)
    }

    func markFailed(_ message: String) async {
        await taskStore.markFailed(message)
    }

    func failDuringExecution(plan: AgentPlan, message: String) async {
        planProgress.update(plan)
        await taskStore.failDuringExecution(plan: plan, message: message)
    }

    private func invocationRequest(
        name: String,
        argumentsJSON: String,
        authorization: ToolAuthorizationRequirement? = nil,
        authorizationEvidence: ToolInvocationAuthorizationEvidence? = nil,
        hookDecision: PreToolUseDecision? = nil,
        hookEvidence: ToolInvocationHookEvidence? = nil,
        mcpWriteRoots: [URL] = [],
        mcpAllowsProtectedMetadataWrites: Bool = false
    ) -> ToolInvocationRequest {
        ToolInvocationRequest(
            name: name,
            argumentsJSON: argumentsJSON,
            tools: tools,
            mcp: mcp,
            pathGuardPolicy: state.pathGuardPolicy,
            activatedSkillNames: skillHost.activatedSkillNames,
            enabledSkills: skillHost.enabledSkills,
            authorizationSkills: skillHost.catalogSkills,
            skillHost: skillHost,
            workPlanKind: state.activeTask?.workPlan?.kind,
            modelSettings: modelSettings(),
            authorization: authorization,
            didResolveAuthorization: true,
            authorizationEvidence: authorizationEvidence,
            hookDecision: hookDecision,
            hookEvidence: hookEvidence,
            mcpWriteRoots: mcpWriteRoots,
            mcpAllowsProtectedMetadataWrites: mcpAllowsProtectedMetadataWrites,
            extraReadAllowlist: MessageAttachment.readAllowlist(
                from: state.events,
                visibleEventIDs: state.modelVisibleAttachmentEventIDs
            )
        )
    }
}
