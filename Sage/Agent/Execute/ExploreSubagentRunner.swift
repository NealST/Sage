//
//  ExploreSubagentRunner.swift
//  Sage
//
//  Read-only nested agent. The loop lives on ExploreTask / Turn.run;
//  this file keeps the tool definition, request decode, and invoke helpers.
//

import Foundation

nonisolated enum ExploreSubagentTool {
    static let name = "explore_subagent"

    static let definition = ToolDefinition(
        name: name,
        description: """
        Delegate a focused read-only filesystem investigation to a nested agent. \
        The child can list directories, read text files, and search files inside the active sandbox. \
        Use when exploration needs several tool rounds but only the final findings belong in the main thread.
        """,
        parameters: .schemaObject(
            properties: [
                "task": .stringProperty("Specific question or investigation for the child agent."),
                "context": .stringProperty("Optional concise context the child needs."),
            ],
            required: ["task"]
        ),
        requiresConfirmation: false
    )
}

@MainActor
enum ExploreSubagentRunner {
    static let maxToolRounds = ExploreTask.maxToolRounds
    static let allowedNames = ExploreTask.allowedNames

    private struct Args: Decodable {
        var task: String
        var context: String?
    }

    static func run(
        argumentsJSON: String,
        settings: ModelSettingsSnapshot,
        tools: ToolRegistry,
        pathGuardPolicy: PathGuard.Policy,
        skillHost: SkillToolHost,
        extraReadAllowlist: [String] = []
    ) async throws -> String {
        let args = try decodeToolArgs(argumentsJSON, as: Args.self)
        let task = args.task.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !task.isEmpty else {
            throw ToolError.invalidArguments("task must not be empty.")
        }
        return try await runTask(
            ExploreSubagentRequest(
                task: task,
                context: args.context,
                instructions: nil,
                settings: settings,
                tools: tools,
                pathGuardPolicy: pathGuardPolicy,
                skillHost: skillHost,
                activatedSkillNames: [],
                enabledSkills: [],
                extraReadAllowlist: extraReadAllowlist
            )
        )
    }

    static func runTask(_ request: ExploreSubagentRequest) async throws -> String {
        let task = ExploreTask(request: request)
        await Turn.run(task, includeTools: true)
        return try task.finish()
    }

    static func initialEvents(for request: ExploreSubagentRequest) -> [AgentEvent] {
        [
            AgentEvent(
                kind: .systemInstruction,
                content: """
                You are Sage's read-only Explore subagent.
                Investigate the assigned question with the available filesystem tools.
                Stay inside this sandbox: \(request.pathGuardPolicy.boundaryDescription)
                Do not propose or perform mutations. Return concise findings with relevant paths and evidence.
                \(request.instructions?.nilIfEmpty ?? "")
                """
            ),
            AgentEvent(
                kind: .userInput,
                content: [request.task, request.context?.nilIfEmpty]
                    .compactMap { $0 }
                    .joined(separator: "\n\nContext:\n")
            ),
        ]
    }

    static func invokeExploreCall(
        _ call: ToolCallProposal,
        allowedNames: Set<String>,
        request: ExploreSubagentRequest
    ) async throws -> String {
        guard allowedNames.contains(call.name) else {
            return "ERROR: Explore subagent cannot call '\(call.name)'."
        }
        do {
            let hookDecision = try await enforceExploreHook(call, request: request)
            var invocation = ToolInvocationRequest(
                name: call.name,
                argumentsJSON: call.argumentsJSON,
                tools: request.tools,
                mcp: nil,
                pathGuardPolicy: request.pathGuardPolicy,
                activatedSkillNames: request.activatedSkillNames,
                enabledSkills: request.enabledSkills,
                skillHost: request.skillHost,
                workPlanKind: .observe,
                modelSettings: nil,
                hookDecision: hookDecision,
                extraReadAllowlist: request.extraReadAllowlist
            ).resolvingAuthorization()
            invocation.authorizationEvidence = request.skillHost.inheritedAuthorizationEvidence(
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

    static func enforceExploreHook(
        _ call: ToolCallProposal,
        request: ExploreSubagentRequest
    ) async throws -> PreToolUseDecision {
        let projectRoot: URL? = if case .project(let root) = request.pathGuardPolicy {
            root
        } else {
            nil
        }
        let activeSkills = request.enabledSkills.filter { skill in
            request.activatedSkillNames.contains(skill.name)
        }
        let hookDecision = await PreToolUseHookEvaluator.shared.evaluate(
            toolName: call.name,
            argumentsJSON: call.argumentsJSON,
            projectRoot: projectRoot,
            activatedSkills: activeSkills
        )
        switch hookDecision {
        case .allow:
            return hookDecision

        case .ask(let approval):
            throw ToolError.operationFailed(
                "PreToolUse hook requires parent approval: \(approval.reason)"
            )

        case .deny(let reason):
            throw ToolError.operationFailed("Blocked by PreToolUse hook: \(reason)")
        }
    }
}
