//
//  explore.swift
//  Sage
//
//  Sage addition (no codex counterpart).
//
//  Read-only Explore subagent on the same `ExecuteTurnLoop` as RegularTask.
//  Isolated events and ModelClient — nothing is written to the parent
//  transcript or occupancy. Codex multi-agent v2 is out of scope.
//

import Foundation

@MainActor
final class ExploreTask: ExecuteTurnLoop {
    static let allowedNames: Set<String> = [
        "list_directory",
        "read_text_file",
        "search_files",
    ]
    static let maxToolRounds = 6

    let request: ExploreSubagentRequest
    private(set) var events: [AgentEvent]
    private(set) var toolBatchCount = 0
    private(set) var findings = "The Explore subagent returned no findings."
    private var cancelled = false
    private var sampleError: Error?

    /// Test seam. Production uses an isolated `ModelClient`.
    var modelSampler: ((Bool) async throws -> ModelTurn)?
    /// Test seam. Production uses `ExploreSubagentRunner.invokeExploreCall`.
    var invokeTool: ((ToolCallProposal) async throws -> String)?

    private let client = ModelClient()

    init(request: ExploreSubagentRequest) {
        self.request = request
        self.events = ExploreSubagentRunner.initialEvents(for: request)
    }

    var canOfferMoreTools: Bool {
        toolBatchCount < Self.maxToolRounds
    }

    func willSample(includeTools: Bool) async {}

    func sample(includeTools: Bool) async throws -> ModelTurn {
        if let modelSampler {
            return try await modelSampler(includeTools)
        }
        let definitions = includeTools
            ? request.tools.definitions.filter { Self.allowedNames.contains($0.name) }
            : []
        return try await client.complete(
            events: events,
            tools: definitions,
            settings: request.settings,
            toolChoice: includeTools ? nil : "none",
            temperature: includeTools ? nil : 0,
            maxTokens: ModelOutputCaps.subagent
        )
    }

    func consume(_ turn: ModelTurn) async -> Turn.StepResult {
        let text = turn.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let calls = turn.toolCalls.map { call in
            ToolCallRecord(id: call.id, name: call.name, argumentsJSON: call.argumentsJSON)
        }
        events.append(AgentEvent(kind: .assistantResponse, content: text, toolCalls: calls))
        guard !turn.toolCalls.isEmpty else {
            findings = text.isEmpty ? "The Explore subagent returned no findings." : text
            return .finished
        }

        toolBatchCount += 1
        do {
            let outputs = try await ParallelToolRuntime.run(calls: turn.toolCalls, invoke: invoke)
            for (call, result) in zip(turn.toolCalls, outputs) {
                events.append(AgentEvent(kind: .toolResult, content: result, toolCallID: call.id))
            }
            return .needsFollowUp
        } catch is CancellationError {
            cancelled = true
            return .finished
        } catch {
            sampleError = error
            return .finished
        }
    }

    func didCancel() async {
        cancelled = true
    }

    func didFail(_ error: Error) async {
        sampleError = error
    }

    func pauseForToolRoundLimit() async {
        events.append(
            AgentEvent(
                kind: .userInput,
                content: "Tool-round limit reached. Summarize the evidence gathered so far without tools."
            )
        )
        do {
            let turn = try await sample(includeTools: false)
            let text = turn.content?.trimmingCharacters(in: .whitespacesAndNewlines)
            findings = text?.nilIfEmpty ?? "The Explore subagent reached its limit without a summary."
        } catch is CancellationError {
            cancelled = true
        } catch {
            sampleError = error
        }
    }

    func finish() throws -> String {
        if let sampleError { throw sampleError }
        if cancelled { throw CancellationError() }
        return findings
    }

    private func invoke(_ call: ToolCallProposal) async throws -> String {
        guard Self.allowedNames.contains(call.name) else {
            return "ERROR: Explore subagent cannot call '\(call.name)'."
        }
        if let invokeTool {
            return try await invokeTool(call)
        }
        return try await ExploreSubagentRunner.invokeExploreCall(
            call,
            allowedNames: Self.allowedNames,
            request: request
        )
    }
}
