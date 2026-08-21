//
//  ExploreSubagentRunner.swift
//  Sage
//
//  Read-only nested agent for focused filesystem exploration.
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
    static let maxToolRounds = 6

    private struct Args: Decodable {
        var task: String
        var context: String?
    }

    static func run(
        argumentsJSON: String,
        settings: ModelSettingsSnapshot,
        tools: ToolRegistry,
        pathGuardPolicy: PathGuard.Policy,
        skillHost: SkillToolHost
    ) async throws -> String {
        let args = try decodeToolArgs(argumentsJSON, as: Args.self)
        let task = args.task.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !task.isEmpty else {
            throw ToolError.invalidArguments("task must not be empty.")
        }
        return try await runTask(
            task: task,
            context: args.context,
            instructions: nil,
            settings: settings,
            tools: tools,
            pathGuardPolicy: pathGuardPolicy,
            skillHost: skillHost,
            activatedSkillNames: [],
            enabledSkills: []
        )
    }

    static func runTask(
        task: String,
        context: String?,
        instructions: String?,
        settings: ModelSettingsSnapshot,
        tools: ToolRegistry,
        pathGuardPolicy: PathGuard.Policy,
        skillHost: SkillToolHost,
        activatedSkillNames: Set<String>,
        enabledSkills: [SkillRecord]
    ) async throws -> String {
        let allowedNames: Set<String> = [
            "list_directory",
            "read_text_file",
            "search_files",
        ]
        let definitions = tools.definitions.filter { allowedNames.contains($0.name) }
        let client = ModelClient()
        var events = [
            AgentEvent(
                kind: .systemInstruction,
                content: """
                You are Sage's read-only Explore subagent.
                Investigate the assigned question with the available filesystem tools.
                Stay inside this sandbox: \(pathGuardPolicy.boundaryDescription)
                Do not propose or perform mutations. Return concise findings with relevant paths and evidence.
                \(instructions?.nilIfEmpty ?? "")
                """
            ),
            AgentEvent(
                kind: .userInput,
                content: [task, context?.nilIfEmpty].compactMap { $0 }.joined(separator: "\n\nContext:\n")
            ),
        ]

        for _ in 0..<maxToolRounds {
            try Task.checkCancellation()
            let turn = try await client.complete(
                events: events,
                tools: definitions,
                settings: settings
            )
            let text = turn.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let calls = turn.toolCalls.map { call in
                ToolCallRecord(id: call.id, name: call.name, argumentsJSON: call.argumentsJSON)
            }
            events.append(
                AgentEvent(kind: .assistantResponse, content: text, toolCalls: calls)
            )

            guard !turn.toolCalls.isEmpty else {
                return text.isEmpty ? "The Explore subagent returned no findings." : text
            }

            for call in turn.toolCalls {
                let result: String
                if allowedNames.contains(call.name) {
                    do {
                        let projectRoot: URL? = if case .project(let root) = pathGuardPolicy {
                            root
                        } else {
                            nil
                        }
                        let activeSkills = enabledSkills.filter { skill in
                            activatedSkillNames.contains(skill.name)
                        }
                        let hookDecision = await PreToolUseHookEvaluator.shared.evaluate(
                            toolName: call.name,
                            argumentsJSON: call.argumentsJSON,
                            projectRoot: projectRoot,
                            activatedSkills: activeSkills
                        )
                        switch hookDecision {
                        case .allow:
                            break

                        case .ask(let reason):
                            throw ToolError.operationFailed(
                                "PreToolUse hook requires parent approval: \(reason)"
                            )

                        case .deny(let reason):
                            throw ToolError.operationFailed(
                                "Blocked by PreToolUse hook: \(reason)"
                            )
                        }
                        result = try await ToolInvocationPipeline.execute(
                            name: call.name,
                            argumentsJSON: call.argumentsJSON,
                            tools: tools,
                            mcp: nil,
                            pathGuardPolicy: pathGuardPolicy,
                            activatedSkillNames: activatedSkillNames,
                            enabledSkills: enabledSkills,
                            skillHost: skillHost,
                            workPlanKind: .observe,
                            modelSettings: nil
                        )
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        result = "ERROR: \(error.localizedDescription)"
                    }
                } else {
                    result = "ERROR: Explore subagent cannot call '\(call.name)'."
                }
                events.append(
                    AgentEvent(
                        kind: .toolResult,
                        content: result,
                        toolCallID: call.id
                    )
                )
            }
        }

        events.append(
            AgentEvent(
                kind: .userInput,
                content: "Tool-round limit reached. Summarize the evidence gathered so far without tools."
            )
        )
        let final = try await client.complete(
            events: events,
            tools: [],
            settings: settings,
            toolChoice: "none",
            temperature: 0
        )
        return final.content?.trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
            ?? "The Explore subagent reached its limit without a summary."
    }
}
