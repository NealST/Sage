//
//  ReviewAgent+Inspect.swift
//  Sage
//
//  The inspect loop is one harness turn: the review model autonomously
//  decides how many read-only tools to call inside `runTurn`, bounded
//  by the turn's token budget instead of a fixed round count. Output
//  parsing (`parse`) and the outer `maxAttempts` retry in `evaluate`
//  are unchanged.
//

import Foundation

extension ReviewAgent {
    func inspect(brief: String) async throws -> ReviewVerdict? {
        // No skill host means inspect tools cannot execute; keep the turn text-only.
        let canInspect = !inspectToolDefinitions().isEmpty && skillHost != nil
        let raw = try await phaseRunner.runTurn(
            profile: PhaseProfile(
                modelRole: .review,
                systemPrompt: Self.systemPrompt,
                tools: modelGateway.availableToolDefinitions(),
                toolAllowlist: canInspect ? Self.inspectToolNames : []
            ),
            userText: brief
        )
        return Self.parse(raw)
    }

    func inspectToolDefinitions() -> [ToolDefinition] {
        modelGateway.tools.definitions.filter { Self.inspectToolNames.contains($0.name) }
    }

    func invokeInspect(_ call: ToolCallProposal) async throws -> String {
        // App-layer fallback: the registry allowlist gate rejects out-of-set
        // calls before this seam, so this only fires on direct dispatch.
        guard Self.inspectToolNames.contains(call.name) else {
            return "ERROR: Review cannot call '\(call.name)'."
        }
        guard let skillHost else {
            return "ERROR: Review inspect tools are unavailable."
        }
        do {
            var invocation = ToolInvocationRequest(
                name: call.name,
                argumentsJSON: call.argumentsJSON,
                tools: modelGateway.tools,
                mcp: nil,
                pathGuardPolicy: state.pathGuardPolicy,
                activatedSkillNames: state.activatedSkillNames,
                enabledSkills: skillHost.enabledSkills,
                skillHost: skillHost,
                workPlanKind: .observe,
                modelSettings: nil
            ).resolvingAuthorization()
            invocation.authorizationEvidence = skillHost.inheritedAuthorizationEvidence(
                name: call.name,
                argumentsJSON: call.argumentsJSON
            )
            return try await ToolOrchestrator.execute(invocation)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return "ERROR: \(error.localizedDescription)"
        }
    }
}
