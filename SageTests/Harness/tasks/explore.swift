@testable import Sage
import SageAsyncUtils
import SageCore
import SageProtocol
import XCTest

/// M4 explore: `explore_subagent` spawns an explorer-role child on the task
/// harness, waits for its final status, and returns its summary as the tool
/// output. These tests drive the child through the manual `turnSampler`
/// installed on the harness thread manager (the fallback sampling path when
/// no model client is attached).
@MainActor
final class ExecuteHarnessExploreTests: XCTestCase {
    private var tempDirectory: URL?
    private var cleanupHarness: TaskHarness?

    override func tearDown() async throws {
        if let harness = cleanupHarness {
            await harness.threadManager.shutdownAllThreadsBounded(.seconds(5))
            await harness.shutdown()
        }
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        try await super.tearDown()
    }

    func testReturnsChildFinalSummary() async throws {
        let runtime = try makeRuntime()
        let harness = try makeHarness(runtime)
        harness.threadManager.setTurnSampler(
            ScriptedExploreSampler(summary: "README has the install steps.")
        )

        let findings = try await runtime.turns.runExploreSubagent(
            task: "What is in README?",
            context: nil,
            instructions: nil
        )

        XCTAssertEqual(findings, "README has the install steps.")
    }

    func testChildInputCarriesFramingTaskAndContext() async throws {
        let runtime = try makeRuntime()
        let harness = try makeHarness(runtime)
        let sampler = ScriptedExploreSampler(summary: "done")
        harness.threadManager.setTurnSampler(sampler)

        _ = try await runtime.turns.runExploreSubagent(
            task: "What is in README?",
            context: "The project root is /tmp",
            instructions: nil
        )

        let firstBatch = try XCTUnwrap(sampler.batches.first)
        let prompt = firstBatch.compactMap(userInputText).joined(separator: "\n")
        XCTAssertTrue(prompt.contains("read-only Explore subagent"))
        XCTAssertTrue(prompt.contains("Task:\nWhat is in README?"))
        XCTAssertTrue(prompt.contains("Context:\nThe project root is /tmp"))
    }

    func testReadToolsDispatchThroughTheHarnessThenSummarize() async throws {
        let runtime = try makeRuntime()
        let harness = try makeHarness(runtime)
        let sampler = ScriptedExploreSampler(
            summary: "two files, no writes.",
            toolRounds: [
                [
                    TurnFunctionCall(callId: "r1", name: "read_text_file", arguments: "{}"),
                    TurnFunctionCall(callId: "l1", name: "list_directory", arguments: "{}"),
                ]
            ]
        )
        harness.threadManager.setTurnSampler(sampler)
        var invoked: [String] = []
        runtime.turns.execute.invokeHarnessTool = { call in
            invoked.append(call.name)
            return "ok:\(call.name)"
        }

        let findings = try await runtime.turns.runExploreSubagent(
            task: "What is here?",
            context: nil,
            instructions: nil
        )

        XCTAssertEqual(findings, "two files, no writes.")
        XCTAssertEqual(invoked, ["read_text_file", "list_directory"])
        XCTAssertEqual(sampler.batches.count, 2)
        let followUp = try XCTUnwrap(sampler.batches.last)
        XCTAssertTrue(followUp.contains { input in
            if case .responseItem(.functionCallOutput(_, let callId, _, _, let output, _)) = input {
                return callId == "r1" && output.textContent == "ok:read_text_file"
            }
            return false
        })
    }

    func testWriteProposalIsRejectedWithoutDispatch() async throws {
        let runtime = try makeRuntime()
        let harness = try makeHarness(runtime)
        let sampler = ScriptedExploreSampler(
            summary: "stayed read-only.",
            toolRounds: [
                [
                    TurnFunctionCall(callId: "w1", name: "write_text_file", arguments: "{}"),
                    TurnFunctionCall(callId: "p1", name: "apply_patch", arguments: "{}"),
                ]
            ]
        )
        harness.threadManager.setTurnSampler(sampler)
        var invoked = 0
        runtime.turns.execute.invokeHarnessTool = { _ in
            invoked += 1
            return "should not run"
        }

        let findings = try await runtime.turns.runExploreSubagent(
            task: "Change something?",
            context: nil,
            instructions: nil
        )

        XCTAssertEqual(findings, "stayed read-only.")
        XCTAssertEqual(invoked, 0)
        XCTAssertEqual(sampler.batches.count, 2)
        let followUp = try XCTUnwrap(sampler.batches.last)
        let rejections = followUp.compactMap { input -> String? in
            if case .responseItem(.functionCallOutput(_, _, _, _, let output, _)) = input {
                return output.textContent
            }
            return nil
        }
        XCTAssertEqual(rejections.count, 2)
        XCTAssertTrue(rejections.allSatisfy { $0.contains("not available for role 'explorer'") })
    }

    func testRoundLimitEndsWithSummaryWithoutFurtherDispatch() async throws {
        let runtime = try makeRuntime()
        let harness = try makeHarness(runtime)
        let readRounds = (0...explorerToolRoundBudget).map { round in
            [TurnFunctionCall(callId: "c\(round + 1)", name: "read_text_file", arguments: "{}")]
        }
        let sampler = ScriptedExploreSampler(summary: "limit summary", toolRounds: readRounds)
        harness.threadManager.setTurnSampler(sampler)
        var invoked = 0
        runtime.turns.execute.invokeHarnessTool = { _ in
            invoked += 1
            return "ok"
        }

        let findings = try await runtime.turns.runExploreSubagent(
            task: "Keep reading",
            context: nil,
            instructions: nil
        )

        XCTAssertEqual(findings, "limit summary")
        XCTAssertEqual(invoked, explorerToolRoundBudget)
        XCTAssertEqual(sampler.batches.count, explorerToolRoundBudget + 2)
        let refusedBatch = try XCTUnwrap(sampler.batches[explorerToolRoundBudget + 1])
        XCTAssertTrue(refusedBatch.contains { input in
            if case .responseItem(.functionCallOutput(_, let callId, _, _, let output, _)) = input {
                return callId == "c\(explorerToolRoundBudget + 1)"
                    && output.textContent?.contains("Tool-round limit reached") == true
            }
            return false
        })
    }

    func testTimeoutThrowsAfterTheWaitBudget() async throws {
        let runtime = try makeRuntime()
        let harness = try makeHarness(runtime)
        harness.threadManager.setTurnSampler(HoldExploreSampler())

        do {
            _ = try await ExploreAgentSpawnRunner.run(
                harness: harness,
                task: "hang",
                context: nil,
                instructions: nil,
                boundaryDescription: "home directory",
                timeoutSeconds: 1
            )
            XCTFail("expected a timeout error")
        } catch {
            XCTAssertTrue(
                error.localizedDescription.contains("Explore subagent timed out after 1 seconds")
            )
        }
    }

    func testChildSamplingErrorSurfacesAsToolFailure() async throws {
        let runtime = try makeRuntime()
        let harness = try makeHarness(runtime)
        harness.threadManager.setTurnSampler(
            ThrowingExploreSampler(message: "model exploded")
        )

        do {
            _ = try await runtime.turns.runExploreSubagent(
                task: "boom",
                context: nil,
                instructions: nil
            )
            XCTFail("expected a tool failure")
        } catch {
            XCTAssertTrue(
                error.localizedDescription.contains("Explore subagent failed: model exploded")
            )
        }
    }

    func testUnconfiguredSettingsThrowInsteadOfSpawning() async throws {
        let runtime = try makeRuntime()
        _ = try makeHarness(runtime)

        do {
            _ = try await runtime.turns.runExploreSubagent(
                task: "anything",
                context: nil,
                instructions: nil
            )
            XCTFail("expected a settings error")
        } catch {
            XCTAssertTrue(
                error.localizedDescription.contains("model settings are unavailable")
            )
        }
    }

    func testParentTranscriptIsUntouched() async throws {
        let runtime = try makeRuntime()
        _ = await runtime.taskStore.createAndActivateTask(relatedTo: [])
        let eventCountBefore = runtime.state.events.count
        let harness = try makeHarness(runtime)
        harness.threadManager.setTurnSampler(
            ScriptedExploreSampler(summary: "isolated findings")
        )

        let findings = try await runtime.turns.runExploreSubagent(
            task: "What is around?",
            context: nil,
            instructions: nil
        )

        XCTAssertEqual(findings, "isolated findings")
        XCTAssertEqual(runtime.state.events.count, eventCountBefore)
        XCTAssertFalse(runtime.state.events.contains { $0.kind == .toolResult })
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

    private func makeHarness(_ runtime: AgentRuntime) throws -> TaskHarness {
        let harness = try XCTUnwrap(runtime.turns.ensureTaskHarness())
        cleanupHarness = harness
        return harness
    }
}

private func userInputText(_ input: TurnInput) -> String? {
    guard case .userInput(let content, _) = input else { return nil }
    return content.compactMap { item -> String? in
        guard case .text(let text, _) = item else { return nil }
        return text
    }.joined(separator: "\n")
}

/// Plays scripted tool rounds, then returns the summary. Round `i` proposes
/// `toolRounds[i]`; once exhausted every sample returns `summary` with no
/// tool calls.
private final class ScriptedExploreSampler: TurnSampler, @unchecked Sendable {
    private let lock = NSLock()
    private let summary: String
    private let toolRounds: [[TurnFunctionCall]]
    private(set) var batches: [[TurnInput]] = []

    init(summary: String, toolRounds: [[TurnFunctionCall]] = []) {
        self.summary = summary
        self.toolRounds = toolRounds
    }

    func sampleTurn(
        turnId: String,
        input: [TurnInput],
        cancellation: CancellationToken
    ) async throws -> TurnSample? {
        _ = turnId
        let count: Int = lock.withLock {
            batches.append(input)
            return batches.count
        }
        if cancellation.isCancelled { return nil }
        if count <= toolRounds.count {
            return TurnSample(functionCalls: toolRounds[count - 1])
        }
        return TurnSample(assistantText: summary)
    }
}

/// Never produces a sample; exits only when the turn is interrupted so the
/// explore wait budget is what times out.
private final class HoldExploreSampler: TurnSampler, @unchecked Sendable {
    func sampleTurn(
        turnId: String,
        input: [TurnInput],
        cancellation: CancellationToken
    ) async throws -> TurnSample? {
        _ = turnId
        _ = input
        while !cancellation.isCancelled {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        return nil
    }
}

private final class ThrowingExploreSampler: TurnSampler, @unchecked Sendable {
    private let message: String

    init(message: String) {
        self.message = message
    }

    func sampleTurn(
        turnId: String,
        input: [TurnInput],
        cancellation: CancellationToken
    ) async throws -> TurnSample? {
        _ = turnId
        _ = input
        _ = cancellation
        throw SageErr.invalidRequest(message)
    }
}
