//
//  ReviewAgent+Inspect.swift
//  Sage
//

import Foundation

extension ReviewAgent {
    func inspect(brief: String, tools: [ToolDefinition]) async throws -> ReviewVerdict? {
        var events = [
            AgentEvent(kind: .systemInstruction, content: Self.systemPrompt),
            AgentEvent(kind: .userInput, content: brief),
        ]
        let canInspect = !tools.isEmpty && skillHost != nil
        for round in 1...Self.maxInspectRounds {
            try Task.checkCancellation()
            let turn = try await modelGateway.completeUnstreamedTurn(
                events: events,
                tools: canInspect ? tools : [],
                role: .review
            )
            let text = turn.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if turn.toolCalls.isEmpty {
                return Self.parse(text)
            }
            let calls = turn.toolCalls.map { call in
                ToolCallRecord(id: call.id, name: call.name, argumentsJSON: call.argumentsJSON)
            }
            events.append(AgentEvent(kind: .assistantResponse, content: text, toolCalls: calls))
            for call in turn.toolCalls {
                try Task.checkCancellation()
                let result = try await invokeInspect(call)
                events.append(AgentEvent(kind: .toolResult, content: result, toolCallID: call.id))
            }
            if round == Self.maxInspectRounds {
                events.append(
                    AgentEvent(
                        kind: .userInput,
                        content: "Inspect limit reached. Output the JSON verdict now. No more tools."
                    )
                )
                let final = try await modelGateway.completeUnstreamedTurn(
                    events: events,
                    tools: [],
                    role: .review,
                    toolChoice: "none"
                )
                return Self.parse(final.content)
            }
        }
        return nil
    }

    func inspectToolDefinitions() -> [ToolDefinition] {
        modelGateway.tools.definitions.filter { Self.inspectToolNames.contains($0.name) }
    }

    func invokeInspect(_ call: ToolCallProposal) async throws -> String {
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
            return try await ToolInvocationPipeline.execute(invocation)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return "ERROR: \(error.localizedDescription)"
        }
    }
}
