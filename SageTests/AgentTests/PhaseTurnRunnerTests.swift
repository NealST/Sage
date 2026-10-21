//
//  PhaseTurnRunnerTests.swift
//  Sage
//
//  M1 acceptance for the review phase turn: the inspect loop is one
//  harness `runTurn`. The assembled prompt carries the review system
//  prompt and the eight read-only tools, mutating calls are refused by
//  the registry gate before dispatch, calls and results land in the
//  transcript for the UI, Stop interrupts, and evaluate's retry/parse
//  behavior is unchanged.
//

@testable import Sage
import SageCore
import SageProtocol
import XCTest

@MainActor
final class PhaseTurnRunnerTests: XCTestCase {
    private var tempDirectory: URL?

    override func tearDown() async throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        try await super.tearDown()
    }

    func testInspectRunsToolsAndParsesVerdict() async throws {
        let runtime = try makeRuntime()
        let reviewer = runtime.turns.reviewer
        _ = try await seedUserTurn(on: runtime, text: "补安装步骤")

        var rounds = 0
        var prompts: [Prompt] = []
        reviewer.phaseRunner.modelSampler = { prompt in
            prompts.append(prompt)
            rounds += 1
            if rounds == 1 {
                return ModelTurn(
                    content: "",
                    toolCalls: [
                        ToolCallProposal(id: "r1", name: "read_text_file", argumentsJSON: "{}"),
                        ToolCallProposal(id: "l1", name: "list_directory", argumentsJSON: "{}"),
                    ]
                )
            }
            return ModelTurn(content: #"{"must_fix":"安装步骤还缺 brew"}"#, toolCalls: [])
        }
        var dispatched: [String] = []
        reviewer.phaseRunner.dispatchTool = { call in
            dispatched.append(call.name)
            return "ok:\(call.name)"
        }

        let verdict = try await reviewer.evaluate(draft: "已经改好了。", workPlan: nil)

        XCTAssertEqual(verdict.mustFix, "安装步骤还缺 brew")
        XCTAssertFalse(verdict.hasOptional)
        XCTAssertEqual(rounds, 2)
        XCTAssertEqual(Set(dispatched), ["read_text_file", "list_directory"])

        // The assembled prompt carries the phase system prompt, the
        // read-only tool set, and the brief as the user message.
        XCTAssertEqual(prompts.count, 2)
        XCTAssertEqual(prompts[0].baseInstructions.text, ReviewAgent.systemPrompt)
        XCTAssertEqual(visibleToolNames(prompts[0]), ReviewAgent.inspectToolNames)
        XCTAssertTrue(promptUserText(prompts[0]).contains("补安装步骤"))
        XCTAssertTrue(promptUserText(prompts[0]).contains("Draft reply"))
        XCTAssertTrue(promptUserText(prompts[0]).contains("已经改好了。"))

        // The follow-up prompt carries the round-one tool outputs.
        XCTAssertEqual(
            Set(promptToolOutputTexts(prompts[1])),
            ["ok:read_text_file", "ok:list_directory"]
        )

        // Calls and results are committed to the transcript so the
        // review process is visible in the UI.
        let toolCalls = runtime.state.events.flatMap { $0.toolCalls ?? [] }
        XCTAssertEqual(Set(toolCalls.map(\.name)), ["read_text_file", "list_directory"])
        let toolResults = runtime.state.events.filter { $0.kind == .toolResult }
        XCTAssertEqual(toolResults.count, 2)
        XCTAssertEqual(Set(toolResults.map(\.toolCallID)), ["r1", "l1"])
        XCTAssertTrue(toolResults.allSatisfy { $0.content.hasPrefix("ok:") })
    }

    func testMutatingToolCallIsRefusedBeforeDispatch() async throws {
        let runtime = try makeRuntime()
        let reviewer = runtime.turns.reviewer
        _ = try await seedUserTurn(on: runtime, text: "改 README")

        var rounds = 0
        var prompts: [Prompt] = []
        reviewer.phaseRunner.modelSampler = { prompt in
            prompts.append(prompt)
            rounds += 1
            if rounds == 1 {
                return ModelTurn(
                    content: "",
                    toolCalls: [
                        ToolCallProposal(id: "w1", name: "write_text_file", argumentsJSON: "{}"),
                        ToolCallProposal(id: "p1", name: "apply_patch", argumentsJSON: "{}"),
                    ]
                )
            }
            return ModelTurn(content: #"{"optional":"目录名可以更短"}"#, toolCalls: [])
        }
        var dispatched = 0
        reviewer.phaseRunner.dispatchTool = { _ in
            dispatched += 1
            return "should not run"
        }

        let verdict = try await reviewer.evaluate(draft: "已经改好了。", workPlan: nil)

        XCTAssertEqual(verdict.optional, "目录名可以更短")
        XCTAssertFalse(verdict.hasMustFix)
        XCTAssertEqual(rounds, 2)
        XCTAssertEqual(dispatched, 0)
        let outputs = promptToolOutputTexts(prompts[1])
        XCTAssertEqual(outputs.count, 2)
        XCTAssertTrue(outputs.allSatisfy { $0.contains("not available this turn") })
        XCTAssertTrue(runtime.state.events.flatMap { $0.toolCalls ?? [] }.isEmpty)
        XCTAssertTrue(runtime.state.events.filter { $0.kind == .toolResult }.isEmpty)
    }

    func testStopInterruptsInspect() async throws {
        let runtime = try makeRuntime()
        let reviewer = runtime.turns.reviewer
        _ = try await seedUserTurn(on: runtime, text: "检查一下")
        reviewer.phaseRunner.modelSampler = { _ in
            ModelTurn(
                content: "",
                toolCalls: [ToolCallProposal(id: "slow", name: "read_text_file", argumentsJSON: "{}")]
            )
        }
        reviewer.phaseRunner.dispatchTool = { _ in
            try await Task.sleep(nanoseconds: 5_000_000_000)
            return "ok"
        }

        let reviewTask = Task {
            try await reviewer.evaluate(draft: "已经改好了。", workPlan: nil)
        }
        try await Task.sleep(nanoseconds: 300_000_000)
        reviewTask.cancel()

        do {
            _ = try await reviewTask.value
            XCTFail("expected cancellation to interrupt the review turn")
        } catch is CancellationError {
        } catch {
            XCTFail("expected CancellationError, got \(error)")
        }
    }

    func testInspectWithoutSkillHostStaysTextOnly() async throws {
        let runtime = try makeRuntime()
        let reviewer = runtime.turns.reviewer
        reviewer.skillHost = nil
        _ = try await seedUserTurn(on: runtime, text: "看一眼 README")

        var rounds = 0
        var prompts: [Prompt] = []
        reviewer.phaseRunner.modelSampler = { prompt in
            prompts.append(prompt)
            rounds += 1
            if rounds == 1 {
                return ModelTurn(
                    content: "",
                    toolCalls: [ToolCallProposal(id: "r1", name: "read_text_file", argumentsJSON: "{}")]
                )
            }
            return ModelTurn(content: #"{"must_fix":"安装步骤还缺 brew"}"#, toolCalls: [])
        }
        var dispatched = 0
        reviewer.phaseRunner.dispatchTool = { _ in
            dispatched += 1
            return "should not run"
        }

        let verdict = try await reviewer.evaluate(draft: "已经改好了。", workPlan: nil)

        XCTAssertEqual(verdict.mustFix, "安装步骤还缺 brew")
        XCTAssertEqual(rounds, 2)
        XCTAssertEqual(dispatched, 0)
        XCTAssertTrue(prompts[0].tools.isEmpty)
        XCTAssertTrue(
            promptToolOutputTexts(prompts[1]).allSatisfy { $0.contains("not available this turn") }
        )
    }

    func testUnusableOutputExhaustsAttempts() async throws {
        let runtime = try makeRuntime()
        let reviewer = runtime.turns.reviewer
        _ = try await seedUserTurn(on: runtime, text: "补安装步骤")

        var samplerCalls = 0
        reviewer.phaseRunner.modelSampler = { _ in
            samplerCalls += 1
            return ModelTurn(content: "我看不出问题在哪里。", toolCalls: [])
        }
        var dispatched = 0
        reviewer.phaseRunner.dispatchTool = { _ in
            dispatched += 1
            return "should not run"
        }

        do {
            _ = try await reviewer.evaluate(draft: "已经改好了。", workPlan: nil)
            XCTFail("expected unusable output to fail evaluate")
        } catch is ReviewEvaluationError {
        } catch {
            XCTFail("expected ReviewEvaluationError, got \(error)")
        }
        XCTAssertEqual(samplerCalls, ReviewAgent.maxAttempts)
        XCTAssertEqual(dispatched, 0)
    }

    private func seedUserTurn(on runtime: AgentRuntime, text: String) async throws -> UUID {
        let created = await runtime.taskStore.createAndActivateTask(relatedTo: [])
        let taskID = try XCTUnwrap(created)
        let persisted = await runtime.taskStore.commit(
            appendEvents: [AgentEvent(kind: .userInput, content: text)],
            deleteEventIDs: []
        ) { _ in }
        XCTAssertTrue(persisted)
        return taskID
    }

    private func makeRuntime() throws -> AgentRuntime {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SageTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        tempDirectory = directory
        let repository = GRDBTaskRepository(
            databaseURL: directory.appendingPathComponent("sage.sqlite"),
            legacyJSONURL: directory.appendingPathComponent("tasks.json")
        )
        return AgentRuntime(
            settings: .shared,
            tools: .makeDefault(),
            taskRepository: repository,
            skills: SkillSessionController()
        )
    }
}

private func visibleToolNames(_ prompt: Prompt) -> Set<String> {
    var names: Set<String> = []
    for tool in prompt.tools {
        if case .object(let fields) = tool,
           case .string(let name)? = fields["name"] {
            names.insert(name)
        }
    }
    return names
}

private func promptUserText(_ prompt: Prompt) -> String {
    prompt.input.compactMap { item -> String? in
        guard case .message(_, let role, let content, _, _) = item, role == "user" else { return nil }
        return content.compactMap { contentItem -> String? in
            if case .inputText(let text) = contentItem { return text }
            return nil
        }.joined(separator: "\n")
    }.joined(separator: "\n")
}

private func promptToolOutputTexts(_ prompt: Prompt) -> [String] {
    prompt.input.compactMap { item -> String? in
        guard case .functionCallOutput(_, _, _, _, let output, _) = item else { return nil }
        return output.body.toText() ?? output.description
    }
}
