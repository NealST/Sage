@testable import Sage
import ApplyPatch
import CodexAPI
import CodexAsyncUtils
import CodexCore
import CodexExecPolicy
import CodexHistory
import CodexHooks
import CodexRollout
import CodexProtocol
import CodexShellCommand
import CodexUtils
import XCTest

final class ExecuteHarnessTurnLoopTests: XCTestCase {
    func testTurnUserInputFlattensUserItemsOnly() {
        let items: [SessionTurnInput] = [
            .userInput(
                content: [
                    .text(text: "hello", textElements: []),
                    .mention(name: "docs", path: "mcp://github"),
                ],
                clientId: nil,
                metadata: UserInputMetadata()
            ),
            .responseItem(
                .message(
                    id: nil,
                    role: "assistant",
                    content: [.outputText(text: "hi")],
                    phase: nil,
                    internalChatMessageMetadataPassthrough: nil
                )
            ),
        ]
        let user = turnUserInput(items)
        XCTAssertEqual(user.count, 2)
        XCTAssertEqual(mcpServerName(from: "mcp://github/issues"), "github")
        XCTAssertEqual(mcpServerNamesMentioned(in: "use mcp://linear and mcp://github/foo"), ["linear", "github"])
    }

    func testCompHashChangedRequiresBothHashes() {
        XCTAssertFalse(compHashChanged(previous: nil, current: "a"))
        XCTAssertFalse(compHashChanged(previous: "a", current: nil))
        XCTAssertFalse(compHashChanged(previous: "a", current: "a"))
        XCTAssertTrue(compHashChanged(previous: "a", current: "b"))
    }

    func testGuardianBasicSessionSource() {
        XCTAssertTrue(Guardian.isBasicSessionSource(.internal(.guardian)))
        XCTAssertTrue(Guardian.isBasicSessionSource(.subAgent(.other("guardian"))))
        XCTAssertFalse(Guardian.isBasicSessionSource(.cli))
        XCTAssertFalse(Guardian.isBasicSessionSource(.subAgent(.review)))
    }

    func testGetLastAssistantMessageFromTurn() {
        let items: [ResponseItem] = [
            .message(
                id: nil,
                role: "user",
                content: [.inputText(text: "q")],
                phase: nil,
                internalChatMessageMetadataPassthrough: nil
            ),
            .message(
                id: nil,
                role: "assistant",
                content: [.outputText(text: "first")],
                phase: nil,
                internalChatMessageMetadataPassthrough: nil
            ),
            .message(
                id: nil,
                role: "assistant",
                content: [.outputText(text: "last")],
                phase: nil,
                internalChatMessageMetadataPassthrough: nil
            ),
        ]
        XCTAssertEqual(getLastAssistantMessageFromTurn(items), "last")
    }

    func testBuildPromptMarksGuardianOutputNonStrict() {
        let turn = TurnContext(sessionSource: .internal(.guardian))
        let step = StepContext(turn: turn)
        let prompt = buildPrompt(input: [], stepContext: step, baseInstructions: BaseInstructions())
        XCTAssertFalse(prompt.outputSchemaStrict)
        XCTAssertTrue(prompt.parallelToolCalls)
    }

    func testContextWindowTokenLimitUsesUsableWindow() {
        let sess = Session()
        sess.state.setTokenUsageFull(100)
        let turn = TurnContext(modelContextWindow: 100, effectiveContextWindowPercent: 95)
        let status = contextWindowTokenStatus(sess: sess, turnContext: turn)
        XCTAssertTrue(status.tokenLimitReached)
        XCTAssertTrue(status.fullContextWindowLimitReached)
    }

    func testRunTurnRecordsUserInputAndReturnsLastAssistantMessage() async throws {
        let sess = Session()
        let turn = TurnContext()
        sess.state.recordItems([
            .message(
                id: nil,
                role: "assistant",
                content: [.outputText(text: "done")],
                phase: nil,
                internalChatMessageMetadataPassthrough: nil
            ),
        ])
        var input: [SessionTurnInput] = [
            TurnInputBuilder.user([.text(text: "hello", textElements: [])]),
        ]
        var requirements = McpStartupRequirements()
        let message = try await runTurn(
            sess: sess,
            turnContext: turn,
            input: &input,
            mcpStartupRequirements: &requirements,
            prewarmedClientSession: nil,
            cancellationToken: CancellationToken()
        )
        XCTAssertEqual(message, "done")
        XCTAssertTrue(sess.cloneHistory().forPrompt().contains { item in
            if case .message(_, let role, let content, _, _) = item, role == "user" {
                return content.contains { part in
                    if case .inputText(let text) = part { return text == "hello" }
                    return false
                }
            }
            return false
        })
        XCTAssertEqual(sess.previousTurnSettingsValue()?.model, turn.model)
    }

    func testUserPromptSubmitScriptSeesTurnPrompt() async {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("sage-ups-source-\(UUID().uuidString)", isDirectory: true)
        let hooks = temp.appendingPathComponent(".sage", isDirectory: true)
        try? FileManager.default.createDirectory(at: hooks, withIntermediateDirectories: true)
        try? #"""
        { "user_prompt_submit": [{ "run": "python3 -c \"import json,sys; d=json.load(sys.stdin); open('prompt.txt','w').write(d.get('prompt','')+'|'+d.get('hook_event_name',''))\"" }] }
        """#.write(to: hooks.appendingPathComponent("hooks.json"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: temp) }

        let sess = Session()
        let turn = TurnContext(cwd: temp.path, model: "gpt-5")
        let outcome = await inspectPendingInput(
            TurnInputBuilder.user([.text(text: "ship the patch", textElements: [])]),
            sess: sess,
            turnContext: turn
        )
        XCTAssertFalse(outcome.shouldStop)
        let written = (try? String(
            contentsOf: temp.appendingPathComponent("prompt.txt"),
            encoding: .utf8
        )) ?? ""
        XCTAssertEqual(written, "ship the patch|UserPromptSubmit")
    }

    func testRunTurnReturnsNilWhenPromptHookBlocks() async throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("sage-turn-hook-\(UUID().uuidString)", isDirectory: true)
        let hooks = temp.appendingPathComponent(".sage", isDirectory: true)
        try FileManager.default.createDirectory(at: hooks, withIntermediateDirectories: true)
        try """
        { "user_prompt_submit": [{ "action": "deny", "reason": "blocked" }] }
        """.write(to: hooks.appendingPathComponent("hooks.json"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: temp) }

        let sess = Session()
        let turn = TurnContext(cwd: temp.path)
        var input: [SessionTurnInput] = [
            TurnInputBuilder.user([.text(text: "secret", textElements: [])]),
        ]
        var requirements = McpStartupRequirements()
        let message = try await runTurn(
            sess: sess,
            turnContext: turn,
            input: &input,
            mcpStartupRequirements: &requirements,
            prewarmedClientSession: nil,
            cancellationToken: CancellationToken()
        )
        XCTAssertNil(message)
        XCTAssertFalse(sess.cloneHistory().forPrompt().contains { item in
            if case .message(_, _, let content, _, _) = item {
                return content.contains { part in
                    if case .inputText(let text) = part { return text.contains("secret") }
                    return false
                }
            }
            return false
        })
    }

    func testRegularSessionTaskEmitsStartAndReturnsLastAssistant() async throws {
        let sess = Session()
        let turn = TurnContext()
        sess.runSamplingOverride = { _, _ in
            SamplingRequestResult(needsFollowUp: false, lastAgentMessage: "done")
        }
        let message = try await RegularSessionTask().run(
            session: sess,
            context: turn,
            input: [TurnInputBuilder.user([.text(text: "hello", textElements: [])])],
            cancellationToken: CancellationToken()
        )
        XCTAssertEqual(message, "done")
        XCTAssertTrue(sess.mcpReprojectionRequested)
        XCTAssertTrue(sess.emittedEvents.contains { event in
            if case .turnStarted(let started) = event {
                return started.turnId == turn.subId
            }
            return false
        })
        XCTAssertEqual(sess.activeTurn?.task?.kind, .regular)
    }

    func testRegularSessionTaskReturnsNilWhenPrepareCancelled() async throws {
        let sess = Session()
        let turn = TurnContext()
        let token = CancellationToken()
        token.cancel()
        let message = try await RegularSessionTask().run(
            session: sess,
            context: turn,
            input: [TurnInputBuilder.user([.text(text: "hello", textElements: [])])],
            cancellationToken: token
        )
        XCTAssertNil(message)
        XCTAssertTrue(sess.mcpReprojectionRequested)
        XCTAssertTrue(sess.emittedEvents.contains { event in
            if case .turnStarted = event { return true }
            return false
        })
    }

    func testRegularSessionTaskLoopsWhenInputArrivesAfterTurn() async throws {
        let sess = Session()
        let turn = TurnContext()
        var samples = 0
        sess.runSamplingOverride = { _, _ in
            samples += 1
            return SamplingRequestResult(needsFollowUp: false, lastAgentMessage: "pass-\(samples)")
        }
        let task = RegularSessionTask()
        task.afterRunTurn = {
            if samples == 1 {
                sess.inputQueue.enqueue(
                    TurnInputBuilder.user([.text(text: "again", textElements: [])])
                )
            }
        }
        let message = try await task.run(
            session: sess,
            context: turn,
            input: [TurnInputBuilder.user([.text(text: "hello", textElements: [])])],
            cancellationToken: CancellationToken()
        )
        XCTAssertEqual(samples, 2)
        XCTAssertEqual(message, "pass-2")
    }

    func testRegularSessionTaskStopsOnTerminalError() async throws {
        let sess = Session()
        let turn = TurnContext()
        var samples = 0
        sess.runSamplingOverride = { _, _ in
            samples += 1
            turn.terminalError = CodexErr.fatal("stop")
            return SamplingRequestResult(needsFollowUp: false, lastAgentMessage: "partial")
        }
        let task = RegularSessionTask()
        task.afterRunTurn = {
            sess.inputQueue.enqueue(
                TurnInputBuilder.user([.text(text: "again", textElements: [])])
            )
        }
        let message = try await task.run(
            session: sess,
            context: turn,
            input: [TurnInputBuilder.user([.text(text: "hello", textElements: [])])],
            cancellationToken: CancellationToken()
        )
        XCTAssertEqual(samples, 1)
        XCTAssertEqual(message, "partial")
    }

    func testSpawnTaskRunsRegularSessionTaskAndEmitsTurnComplete() async throws {
        let sess = Session()
        let turn = TurnContext()
        sess.runSamplingOverride = { _, _ in
            SamplingRequestResult(needsFollowUp: false, lastAgentMessage: "spawned")
        }
        await sess.spawnTask(
            RegularSessionTask(),
            turnContext: turn,
            input: [TurnInputBuilder.user([.text(text: "hello", textElements: [])])]
        )
        XCTAssertEqual(sess.lastTaskAgentMessage, "spawned")
        XCTAssertNil(sess.lastTurnAbortReason)
        XCTAssertNil(sess.activeTurn)
        XCTAssertTrue(sess.emittedEvents.contains { event in
            if case .turnStarted(let started) = event { return started.turnId == turn.subId }
            return false
        })
        XCTAssertTrue(sess.emittedEvents.contains { event in
            if case .turnComplete(let complete) = event { return complete.turnId == turn.subId }
            return false
        })
    }

    func testSpawnTaskReplacesInFlightTurn() async {
        let sess = Session()
        sess.activeTurn = ActiveTurn(
            task: RunningTask(kind: .review, turnContext: TurnContext()),
            turnState: TurnState()
        )
        sess.runSamplingOverride = { _, _ in
            SamplingRequestResult(needsFollowUp: false, lastAgentMessage: "next")
        }
        await sess.spawnTask(
            RegularSessionTask(),
            turnContext: TurnContext(),
            input: [TurnInputBuilder.user([.text(text: "hello", textElements: [])])]
        )
        XCTAssertEqual(sess.lastTurnAbortReason, nil)
        XCTAssertEqual(sess.lastTaskAgentMessage, "next")
        XCTAssertTrue(sess.emittedEvents.contains { event in
            if case .turnAborted(let aborted) = event { return aborted.reason == .replaced }
            return false
        })
    }

    func testSubmitStartsRegularTurnWhenIdle() async throws {
        let sess = Session()
        sess.runSamplingOverride = { _, _ in
            SamplingRequestResult(needsFollowUp: false, lastAgentMessage: "from-submit")
        }
        let id = try await sess.submit(
            .userInput(TurnInputBuilder.user([.text(text: "hello", textElements: [])]))
        )
        XCTAssertFalse(id.isEmpty)
        await sess.waitUntilIdle()
        XCTAssertEqual(sess.lastTaskAgentMessage, "from-submit")
        XCTAssertNil(sess.activeTurn)
        XCTAssertTrue(sess.emittedEvents.contains { event in
            if case .turnComplete = event { return true }
            return false
        })
    }

    func testSubmitWhileSamplingSteersTheNextLoop() async throws {
        let sess = Session()
        let firstSample = expectation(description: "first sample")
        let gate = SubmissionAck()
        var samples = 0
        sess.runSamplingOverride = { _, _ in
            samples += 1
            if samples == 1 {
                firstSample.fulfill()
                await gate.wait()
            }
            return SamplingRequestResult(needsFollowUp: false, lastAgentMessage: "pass-\(samples)")
        }
        let turn = TurnContext()
        let running = Task {
            await sess.spawnTask(
                RegularSessionTask(),
                turnContext: turn,
                input: [TurnInputBuilder.user([.text(text: "hello", textElements: [])])]
            )
        }
        await fulfillment(of: [firstSample], timeout: 1)
        _ = try await sess.submit(
            .userInput(TurnInputBuilder.user([.text(text: "again", textElements: [])]))
        )
        gate.signal()
        await running.value
        XCTAssertEqual(samples, 2)
        XCTAssertEqual(sess.lastTaskAgentMessage, "pass-2")
    }

    func testSubmitInterruptAbortsInFlightTurn() async throws {
        let sess = Session()
        let token = CancellationToken()
        let entered = expectation(description: "sampling")
        sess.runSamplingOverride = { _, _ in
            entered.fulfill()
            while !token.isCancelled {
                try await Task.sleep(for: .milliseconds(10))
            }
            throw CodexErr(details: .turnAborted)
        }
        let running = Task {
            await sess.spawnTask(
                RegularSessionTask(),
                turnContext: TurnContext(),
                input: [TurnInputBuilder.user([.text(text: "hello", textElements: [])])],
                cancellationToken: token
            )
        }
        await fulfillment(of: [entered], timeout: 1)
        _ = try await sess.submit(.interrupt)
        await running.value
        XCTAssertEqual(sess.lastTurnAbortReason, .interrupted)
        XCTAssertNil(sess.activeTurn)
        XCTAssertTrue(sess.emittedEvents.contains { event in
            if case .turnAborted(let aborted) = event { return aborted.reason == .interrupted }
            return false
        })
    }

    func testSubmitInterAgentTriggerStartsATurn() async throws {
        let sess = Session()
        sess.runSamplingOverride = { _, _ in
            SamplingRequestResult(needsFollowUp: false, lastAgentMessage: "mailbox")
        }
        _ = try await sess.submit(
            .interAgent(
                InterAgentCommunication(
                    author: .root(),
                    recipient: .root(),
                    otherRecipients: [],
                    content: "wake",
                    triggerTurn: true
                )
            )
        )
        await sess.waitUntilIdle()
        XCTAssertEqual(sess.lastTaskAgentMessage, "mailbox")
    }

    func testNewTurnContextAppliesStartOptionsToPrompt() {
        let schema = CodexProtocol.JSONValue.object(["type": .string("object")])
        let sess = Session()
        let turn = sess.newTurnContext(
            subId: "turn-1",
            options: NewTurnContextOptions(
                start: TurnStartOptions(
                    turnTrigger: "retry",
                    finalOutputJsonSchema: schema,
                    serviceTier: "priority",
                    parentTurnId: "parent",
                    rootTurnId: "root",
                    cyberAccessProgram: .standard
                ),
                initiatingAgentPath: AgentPath.root()
            )
        )
        XCTAssertEqual(turn.subId, "turn-1")
        XCTAssertEqual(turn.turnTrigger, "retry")
        XCTAssertEqual(turn.finalOutputJsonSchema, schema)
        XCTAssertEqual(turn.nextStepSettings.serviceTier, "priority")
        XCTAssertEqual(turn.parentTurnId, "parent")
        XCTAssertEqual(turn.rootTurnId, "root")
        XCTAssertEqual(turn.cyberAccessProgram, .standard)
        XCTAssertEqual(turn.initiatingAgentPath, AgentPath.root())
        let prompt = buildPrompt(
            input: [],
            stepContext: StepContext(turn: turn),
            baseInstructions: BaseInstructions()
        )
        XCTAssertEqual(prompt.outputSchema, schema)
        XCTAssertEqual(prompt.cyberAccessProgram, .standard)
    }

    func testMailboxStartOptionsLandOnTheTurn() async throws {
        let sess = Session()
        sess.runSamplingOverride = { _, _ in
            SamplingRequestResult(needsFollowUp: false, lastAgentMessage: "woke")
        }
        let author = try AgentPath.root().join("ada")
        _ = try await sess.submit(
            .interAgent(
                InterAgentCommunication(
                    author: author,
                    recipient: .root(),
                    otherRecipients: [],
                    content: "wake",
                    triggerTurn: true
                )
            ),
            startOptions: TurnStartOptions(
                turnTrigger: "agent",
                parentTurnId: "parent-turn",
                rootTurnId: "root-turn",
                cyberAccessProgram: .daybreakBlue
            )
        )
        await sess.waitUntilIdle()
        let turn = try XCTUnwrap(sess.lastStartedTurnContext)
        XCTAssertEqual(turn.turnTrigger, "agent")
        XCTAssertEqual(turn.parentTurnId, "parent-turn")
        XCTAssertEqual(turn.rootTurnId, "root-turn")
        XCTAssertEqual(turn.cyberAccessProgram, .daybreakBlue)
        XCTAssertEqual(turn.initiatingAgentPath, author)
        XCTAssertEqual(sess.lastTaskAgentMessage, "woke")
    }

    func testSubmitUserInputStartOptionsLandOnTheTurn() async throws {
        let sess = Session()
        sess.runSamplingOverride = { _, _ in
            SamplingRequestResult(needsFollowUp: false, lastAgentMessage: "started")
        }
        let schema = CodexProtocol.JSONValue.object(["type": .string("object")])
        _ = try await sess.submit(
            .userInput(TurnInputBuilder.user([.text(text: "hello", textElements: [])])),
            startOptions: TurnStartOptions(
                turnTrigger: "retry",
                finalOutputJsonSchema: schema,
                parentTurnId: "parent-turn",
                rootTurnId: "root-turn",
                cyberAccessProgram: .standard
            )
        )
        await sess.waitUntilIdle()
        let turn = try XCTUnwrap(sess.lastStartedTurnContext)
        XCTAssertEqual(turn.turnTrigger, "retry")
        XCTAssertEqual(turn.finalOutputJsonSchema, schema)
        XCTAssertEqual(turn.parentTurnId, "parent-turn")
        XCTAssertEqual(turn.rootTurnId, "root-turn")
        XCTAssertEqual(turn.cyberAccessProgram, .standard)
        XCTAssertEqual(sess.lastTaskAgentMessage, "started")
    }

    func testQueueOnlyMailboxWakesDurableSleepWithReferenceCyberProgram() async throws {
        let sess = Session()
        sess.runSamplingOverride = { _, _ in
            SamplingRequestResult(needsFollowUp: false, lastAgentMessage: "slept")
        }
        _ = try await sess.submit(
            .interAgent(
                InterAgentCommunication(
                    author: .root(),
                    recipient: .root(),
                    otherRecipients: [],
                    content: "queued",
                    triggerTurn: false
                )
            )
        )
        await sess.waitUntilIdle()
        XCTAssertNil(sess.lastStartedTurnContext)

        sess.services.outstandingDurableSleep = true
        sess.state.history.setReferenceContextItem(
            TurnContextItem(
                cwd: "/",
                model: "gpt-5",
                cyberAccessProgram: .daybreakBlue
            )
        )
        _ = try await sess.submit(
            .interAgent(
                InterAgentCommunication(
                    author: .root(),
                    recipient: .root(),
                    otherRecipients: [],
                    content: "wake",
                    triggerTurn: false
                )
            )
        )
        await sess.waitUntilIdle()
        let turn = try XCTUnwrap(sess.lastStartedTurnContext)
        XCTAssertEqual(turn.cyberAccessProgram, .daybreakBlue)
        XCTAssertNil(turn.initiatingAgentPath)
        XCTAssertEqual(sess.lastTaskAgentMessage, "slept")
    }

    func testSubmitReviewStartsTurnWithResolvedPrompt() async throws {
        let sess = Session()
        sess.state.sessionConfiguration.originalConfig.reviewModel = "review-model"
        sess.state.sessionConfiguration.originalConfig.features.enable(.webSearchRequest)
        sess.state.sessionConfiguration.originalConfig.features.enable(.webSearchCached)
        sess.state.sessionConfiguration.originalConfig.features.enable(.goals)
        var sampled = ""
        sess.runSamplingOverride = { input, _ in
            sampled = input.map { String(describing: $0) }.joined(separator: "\n")
            return SamplingRequestResult(needsFollowUp: false, lastAgentMessage: "looks fine")
        }
        _ = try await sess.submit(
            .review(ReviewRequest(target: .custom(instructions: "Check the parser")))
        )
        await sess.waitUntilIdle()
        let turn = try XCTUnwrap(sess.lastStartedTurnContext)
        XCTAssertEqual(turn.model, "review-model")
        XCTAssertEqual(turn.nextStepSettings.modelSnapshot.slug, "review-model")
        XCTAssertFalse(turn.config.features.enabled(.webSearchRequest))
        XCTAssertFalse(turn.config.features.enabled(.webSearchCached))
        XCTAssertFalse(turn.config.features.enabled(.goals))
        XCTAssertTrue(sampled.contains("Check the parser"))
        XCTAssertEqual(sess.lastTaskAgentMessage, "looks fine")
        XCTAssertFalse(sess.isReviewTaskActive())
        XCTAssertTrue(sess.emittedEvents.contains { event in
            if case .itemStarted(let started) = event,
               case .enteredReviewMode(let item) = started.item
            {
                return item.target == .custom(instructions: "Check the parser")
                    && item.userFacingHint == "Check the parser"
            }
            return false
        })
        XCTAssertTrue(sess.emittedEvents.contains { event in
            if case .itemCompleted(let completed) = event,
               case .exitedReviewMode(let item) = completed.item
            {
                return item.reviewOutput?.overallExplanation == "looks fine"
            }
            return false
        })
    }

    func testSubmitReviewRejectsEmptyCustomPrompt() async throws {
        let sess = Session()
        _ = try await sess.submit(.review(ReviewRequest(target: .custom(instructions: "  \n"))))
        await sess.waitUntilIdle()
        XCTAssertNil(sess.lastStartedTurnContext)
        XCTAssertTrue(sess.emittedEvents.contains { event in
            if case .error(let error) = event {
                return error.message.contains("Review prompt cannot be empty")
            }
            return false
        })
    }

    func testThreadSettingsUpdateWithoutStartingATurn() async throws {
        let sess = Session()
        sess.state.sessionConfiguration.stepSettings.model = "gpt-5"
        _ = try await sess.submit(
            .threadSettings(
                ThreadSettingsOverrides(
                    model: "gpt-5-mini",
                    reasoningEffort: .low,
                    reasoningSummary: .concise,
                    mode: .plan
                )
            )
        )
        XCTAssertNil(sess.activeTurn)
        XCTAssertNil(sess.lastStartedTurnId)
        XCTAssertFalse(sess.emittedEvents.contains { event in
            if case .turnStarted = event { return true }
            return false
        })
        let settings = sess.state.sessionConfiguration.stepSettings
        XCTAssertEqual(settings.model, "gpt-5-mini")
        XCTAssertEqual(settings.modelSnapshot.slug, "gpt-5-mini")
        XCTAssertEqual(settings.reasoningEffort, .low)
        XCTAssertEqual(settings.reasoningSummary, .concise)
        XCTAssertEqual(settings.collaborationMode?.mode, .plan)
        XCTAssertTrue(sess.emittedEvents.contains { event in
            if case .threadSettingsApplied(let applied) = event {
                return applied.threadId == sess.threadId
                    && applied.threadSettings.model == "gpt-5-mini"
                    && applied.threadSettings.reasoningEffort == .low
                    && applied.threadSettings.reasoningSummary == .concise
                    && applied.threadSettings.collaborationMode.mode == .plan
            }
            return false
        })
        let next = sess.newTurnContext(subId: "next")
        XCTAssertEqual(next.model, "gpt-5-mini")
        XCTAssertEqual(next.collaborationModeValue()?.mode, .plan)
        XCTAssertEqual(next.nextStepSettings.reasoningSummary, .concise)
    }

    func testThreadSettingsRejectsEmptyModel() async throws {
        let sess = Session()
        sess.state.sessionConfiguration.stepSettings.model = "gpt-5"
        _ = try await sess.submit(.threadSettings(ThreadSettingsOverrides(model: "  ")))
        XCTAssertEqual(sess.state.sessionConfiguration.stepSettings.model, "gpt-5")
        XCTAssertNil(sess.lastStartedTurnId)
        XCTAssertNil(sess.activeTurn)
        XCTAssertTrue(sess.emittedEvents.contains { event in
            if case .error(let error) = event {
                return error.message.contains("invalid thread settings override:")
                    && error.errorInfo == .badRequest
            }
            return false
        })
        XCTAssertFalse(sess.emittedEvents.contains { event in
            if case .threadSettingsApplied = event { return true }
            return false
        })
    }

    func testThreadSettingsLeaveTheRunningTurnAlone() async throws {
        let sess = Session()
        sess.state.sessionConfiguration.stepSettings.model = "gpt-5"
        let entered = expectation(description: "sampling")
        let gate = SubmissionAck()
        sess.runSamplingOverride = { _, _ in
            entered.fulfill()
            await gate.wait()
            return SamplingRequestResult(needsFollowUp: false, lastAgentMessage: "kept")
        }
        _ = try await sess.submit(
            .userInput(TurnInputBuilder.user([.text(text: "hello", textElements: [])]))
        )
        await fulfillment(of: [entered], timeout: 1)
        XCTAssertEqual(sess.activeTurn?.task?.turnContext.model, "gpt-5")
        XCTAssertNotNil(sess.lastStartedTurnId)
        let started = sess.emittedEvents.filter { event in
            if case .turnStarted = event { return true }
            return false
        }.count
        _ = try await sess.submit(
            .threadSettings(
                ThreadSettingsOverrides(
                    model: "gpt-5-mini",
                    reasoningEffort: .low,
                    reasoningSummary: .concise,
                    mode: .plan
                )
            )
        )
        XCTAssertEqual(sess.activeTurn?.task?.turnContext.model, "gpt-5")
        XCTAssertNil(sess.activeTurn?.task?.turnContext.collaborationMode)
        XCTAssertEqual(sess.state.sessionConfiguration.stepSettings.model, "gpt-5-mini")
        XCTAssertNil(sess.lastStartedTurnId)
        XCTAssertEqual(
            sess.emittedEvents.filter { event in
                if case .turnStarted = event { return true }
                return false
            }.count,
            started
        )
        gate.signal()
        await sess.waitUntilIdle()
        XCTAssertEqual(sess.lastTaskAgentMessage, "kept")
        let next = sess.newTurnContext(subId: "next")
        XCTAssertEqual(next.model, "gpt-5-mini")
        XCTAssertEqual(next.collaborationModeValue()?.mode, .plan)
    }

    func testTurnSettingsPublishOntoTheRunningTurnOnly() async throws {
        let sess = Session()
        sess.features.enable(.stepModelSwitching)
        sess.state.sessionConfiguration.stepSettings.model = "gpt-5"
        let entered = expectation(description: "sampling")
        let gate = SubmissionAck()
        var sampledModels: [String] = []
        sess.runSamplingOverride = { _, step in
            sampledModels.append(step.settings.model)
            if sampledModels.count == 1 {
                entered.fulfill()
                await gate.wait()
                return SamplingRequestResult(needsFollowUp: true, lastAgentMessage: nil)
            }
            return SamplingRequestResult(needsFollowUp: false, lastAgentMessage: "switched")
        }
        _ = try await sess.submit(
            .userInput(TurnInputBuilder.user([.text(text: "hello", textElements: [])]))
        )
        await fulfillment(of: [entered], timeout: 1)
        let turnId = try XCTUnwrap(sess.lastStartedTurnId)
        let started = sess.emittedEvents.filter { event in
            if case .turnStarted = event { return true }
            return false
        }.count
        _ = try await sess.submit(
            .turnSettings(
                turnId: turnId,
                update: TurnSettingsUpdate(
                    model: "gpt-5-mini",
                    reasoningEffort: .low,
                    reasoningSummary: .concise,
                    serviceTier: "priority"
                )
            )
        )
        XCTAssertEqual(sess.lastTurnSettingsOutcome, .applied)
        XCTAssertEqual(sess.activeTurn?.task?.turnContext.model, "gpt-5")
        XCTAssertEqual(sess.activeTurn?.task?.turnContext.nextStepSettings.model, "gpt-5-mini")
        XCTAssertEqual(sess.activeTurn?.task?.turnContext.nextStepSettings.reasoningEffort, .low)
        XCTAssertEqual(sess.activeTurn?.task?.turnContext.nextStepSettings.reasoningSummary, .concise)
        XCTAssertEqual(sess.activeTurn?.task?.turnContext.nextStepSettings.serviceTier, "priority")
        XCTAssertEqual(sess.state.sessionConfiguration.stepSettings.model, "gpt-5")
        XCTAssertEqual(sess.lastStartedTurnId, turnId)
        XCTAssertEqual(
            sess.emittedEvents.filter { event in
                if case .turnStarted = event { return true }
                return false
            }.count,
            started
        )
        gate.signal()
        await sess.waitUntilIdle()
        XCTAssertEqual(sampledModels, ["gpt-5", "gpt-5-mini"])
        XCTAssertEqual(sess.lastTaskAgentMessage, "switched")
        XCTAssertEqual(sess.newTurnContext(subId: "later").model, "gpt-5")
    }

    func testTurnSettingsRequireTheFeatureAndALiveTurn() async throws {
        let sess = Session()
        sess.state.sessionConfiguration.stepSettings.model = "gpt-5"
        _ = try await sess.submit(
            .turnSettings(turnId: "missing", update: TurnSettingsUpdate(model: "gpt-5-mini"))
        )
        XCTAssertEqual(
            sess.lastTurnSettingsOutcome,
            .rejected(reason: "turn settings updates require the step_model_switching feature")
        )
        XCTAssertEqual(sess.state.sessionConfiguration.stepSettings.model, "gpt-5")
        XCTAssertNil(sess.activeTurn)

        sess.features.enable(.stepModelSwitching)
        _ = try await sess.submit(
            .turnSettings(turnId: "missing", update: TurnSettingsUpdate(model: "gpt-5-mini"))
        )
        XCTAssertEqual(sess.lastTurnSettingsOutcome, .targetUnavailable)

        let entered = expectation(description: "sampling")
        let gate = SubmissionAck()
        sess.runSamplingOverride = { _, _ in
            entered.fulfill()
            await gate.wait()
            return SamplingRequestResult(needsFollowUp: false, lastAgentMessage: "kept")
        }
        _ = try await sess.submit(
            .userInput(TurnInputBuilder.user([.text(text: "hello", textElements: [])]))
        )
        await fulfillment(of: [entered], timeout: 1)
        let turnId = try XCTUnwrap(sess.activeTurn?.task?.turnContext.subId)
        _ = try await sess.submit(
            .turnSettings(turnId: "other-turn", update: TurnSettingsUpdate(model: "gpt-5-mini"))
        )
        XCTAssertEqual(sess.lastTurnSettingsOutcome, .targetUnavailable)
        XCTAssertEqual(sess.activeTurn?.task?.turnContext.nextStepSettings.model, "gpt-5")

        _ = try await sess.submit(
            .turnSettings(turnId: turnId, update: TurnSettingsUpdate(model: "  "))
        )
        XCTAssertEqual(
            sess.lastTurnSettingsOutcome,
            .rejected(reason: "model must be a non-empty slug without surrounding whitespace")
        )
        XCTAssertEqual(sess.activeTurn?.task?.turnContext.nextStepSettings.model, "gpt-5")

        sess.activeTurn?.task?.cancellationToken?.cancel()
        _ = try await sess.submit(
            .turnSettings(turnId: turnId, update: TurnSettingsUpdate(model: "gpt-5-mini"))
        )
        XCTAssertEqual(sess.lastTurnSettingsOutcome, .targetUnavailable)
        XCTAssertEqual(sess.activeTurn?.task?.turnContext.model, "gpt-5")
        XCTAssertEqual(sess.activeTurn?.task?.turnContext.nextStepSettings.model, "gpt-5")
        XCTAssertEqual(sess.state.sessionConfiguration.stepSettings.model, "gpt-5")
        gate.signal()
        await sess.waitUntilIdle()
    }

    func testInterruptIfNoPendingInputAbortsOnlyAQuietTurn() async throws {
        let sess = Session()
        _ = try await sess.submit(.interruptIfNoPendingInput(turnId: "missing"))
        XCTAssertEqual(sess.lastInterruptIfNoPendingInput, false)
        XCTAssertNil(sess.activeTurn)

        let entered = expectation(description: "sampling")
        let gate = SubmissionAck()
        sess.runSamplingOverride = { _, _ in
            entered.fulfill()
            await gate.wait()
            return SamplingRequestResult(needsFollowUp: false, lastAgentMessage: "kept")
        }
        _ = try await sess.submit(
            .userInput(TurnInputBuilder.user([.text(text: "hello", textElements: [])]))
        )
        await fulfillment(of: [entered], timeout: 1)
        let turnId = try XCTUnwrap(sess.activeTurn?.task?.turnContext.subId)

        _ = try await sess.submit(.interruptIfNoPendingInput(turnId: "other-turn"))
        XCTAssertEqual(sess.lastInterruptIfNoPendingInput, false)
        XCTAssertEqual(sess.activeTurn?.task?.turnContext.subId, turnId)
        XCTAssertNil(sess.lastTurnAbortReason)

        sess.activeTurn?.turnState.pendingInput.enqueue(
            TurnInputBuilder.user([.text(text: "queued", textElements: [])])
        )
        _ = try await sess.submit(.interruptIfNoPendingInput(turnId: turnId))
        XCTAssertEqual(sess.lastInterruptIfNoPendingInput, false)
        XCTAssertEqual(sess.activeTurn?.task?.turnContext.subId, turnId)
        sess.activeTurn?.turnState.pendingInput.items.removeAll()

        _ = try await sess.submit(
            .userInput(TurnInputBuilder.user([.text(text: "steer", textElements: [])]))
        )
        _ = try await sess.submit(.interruptIfNoPendingInput(turnId: turnId))
        XCTAssertEqual(sess.lastInterruptIfNoPendingInput, false)
        XCTAssertEqual(sess.activeTurn?.task?.turnContext.subId, turnId)
        XCTAssertTrue(sess.inputQueue.hasSessionPendingItems())

        _ = try await sess.submit(
            .interAgent(
                InterAgentCommunication(
                    author: .root(),
                    recipient: .root(),
                    otherRecipients: [],
                    content: "hold",
                    triggerTurn: false
                )
            )
        )
        sess.inputQueue.takeAll()
        _ = try await sess.submit(.interruptIfNoPendingInput(turnId: turnId))
        XCTAssertEqual(sess.lastInterruptIfNoPendingInput, false)
        XCTAssertTrue(sess.inputQueue.hasPendingMailboxItems())
        XCTAssertNotNil(sess.activeTurn)

        sess.inputQueue.drainMailboxInputItems()
        _ = try await sess.submit(.interruptIfNoPendingInput(turnId: turnId))
        XCTAssertEqual(sess.lastInterruptIfNoPendingInput, true)
        XCTAssertNil(sess.activeTurn)
        XCTAssertEqual(sess.lastTurnAbortReason, .interrupted)
        XCTAssertTrue(sess.emittedEvents.contains { event in
            if case .turnAborted(let aborted) = event {
                return aborted.turnId == turnId && aborted.reason == .interrupted
            }
            return false
        })
        gate.signal()
        await sess.waitUntilIdle()
    }

    func testRecoverTurnResumesTheInterruptedTurn() async throws {
        let sess = Session()
        sess.state.sessionConfiguration.stepSettings.model = "gpt-5"
        sess.state.history.setReferenceContextItem(
            TurnContextItem(
                turnId: "turn-kept",
                rootTurnId: "root-kept",
                cwd: "/",
                model: "gpt-5"
            )
        )
        var sampled = ""
        var sampledTurnId = ""
        var sampledTrigger: String?
        sess.runSamplingOverride = { input, step in
            sampled = input.map { String(describing: $0) }.joined(separator: "\n")
            sampledTurnId = step.turn.subId
            sampledTrigger = step.turn.turnTrigger
            return SamplingRequestResult(needsFollowUp: false, lastAgentMessage: "resumed")
        }
        _ = try await sess.submit(
            .recoverTurn(
                RecoverTurnRequest(
                    turnId: "turn-kept",
                    threadSettings: ThreadSettingsOverrides(model: "gpt-5-mini", mode: .plan),
                    cyberAccessProgram: .daybreakBlue
                )
            )
        )
        await sess.waitUntilIdle()
        XCTAssertEqual(sess.lastTurnInputSubmission, .started(turnId: "turn-kept"))
        XCTAssertNil(sess.lastTurnInputError)
        XCTAssertEqual(sampledTurnId, "turn-kept")
        XCTAssertEqual(sampledTrigger, "retry")
        XCTAssertEqual(sampled, "")
        XCTAssertEqual(sess.lastTaskAgentMessage, "resumed")
        XCTAssertEqual(sess.lastStartedTurnId, "turn-kept")
        let turn = try XCTUnwrap(sess.lastStartedTurnContext)
        XCTAssertEqual(turn.model, "gpt-5-mini")
        XCTAssertEqual(turn.collaborationModeValue()?.mode, .plan)
        XCTAssertEqual(turn.cyberAccessProgram, .daybreakBlue)
        XCTAssertEqual(turn.rootTurnId, "root-kept")
        XCTAssertEqual(sess.state.sessionConfiguration.stepSettings.model, "gpt-5-mini")
        XCTAssertTrue(sess.emittedEvents.contains { event in
            if case .turnStarted(let started) = event {
                return started.turnId == "turn-kept" && started.model == "gpt-5-mini"
            }
            return false
        })
    }

    func testRecoverTurnLeavesABusyOrBlockedThreadUnchanged() async throws {
        let sess = Session()
        sess.state.sessionConfiguration.stepSettings.model = "gpt-5"
        sess.state.sessionConfiguration.stepSettings.collaborationMode = CollaborationMode(
            mode: .plan,
            settings: Settings(model: "gpt-5")
        )
        sess.inputQueue.enqueueMailboxCommunication(
            InterAgentCommunication(
                author: .root(),
                recipient: .root(),
                otherRecipients: [],
                content: "wake",
                triggerTurn: true
            )
        )
        _ = try await sess.submit(
            .recoverTurn(
                RecoverTurnRequest(
                    turnId: "blocked",
                    threadSettings: ThreadSettingsOverrides(model: " ")
                )
            )
        )
        XCTAssertEqual(sess.lastTurnInputSubmission, .notSubmitted(reason: .pendingTriggerTurn))
        XCTAssertNil(sess.lastTurnInputError)
        XCTAssertEqual(sess.state.sessionConfiguration.stepSettings.model, "gpt-5")
        XCTAssertNil(sess.activeTurn)
        XCTAssertTrue(sess.inputQueue.hasTriggerTurnMailboxItems())
        _ = sess.inputQueue.drainMailboxInputItems()

        let entered = expectation(description: "sampling")
        let gate = SubmissionAck()
        sess.runSamplingOverride = { _, _ in
            entered.fulfill()
            await gate.wait()
            return SamplingRequestResult(needsFollowUp: false, lastAgentMessage: "busy")
        }
        _ = try await sess.submit(
            .userInput(TurnInputBuilder.user([.text(text: "hello", textElements: [])]))
        )
        await fulfillment(of: [entered], timeout: 1)
        let runningId = sess.activeTurn?.task?.turnContext.subId
        _ = try await sess.submit(
            .recoverTurn(
                RecoverTurnRequest(
                    turnId: "other",
                    threadSettings: ThreadSettingsOverrides(model: "gpt-5-mini")
                )
            )
        )
        XCTAssertEqual(sess.lastTurnInputSubmission, .notSubmitted(reason: .notIdle))
        XCTAssertEqual(sess.state.sessionConfiguration.stepSettings.model, "gpt-5")
        XCTAssertEqual(sess.activeTurn?.task?.turnContext.subId, runningId)
        XCTAssertEqual(sess.activeTurn?.task?.turnContext.model, "gpt-5")
        gate.signal()
        await sess.waitUntilIdle()

        _ = try await sess.submit(
            .recoverTurn(
                RecoverTurnRequest(
                    turnId: "bad-model",
                    threadSettings: ThreadSettingsOverrides(model: " ")
                )
            )
        )
        XCTAssertNil(sess.lastTurnInputSubmission)
        XCTAssertTrue(sess.lastTurnInputError?.contains("invalid thread settings override:") == true)
        XCTAssertEqual(sess.state.sessionConfiguration.stepSettings.model, "gpt-5")
        XCTAssertEqual(sess.state.sessionConfiguration.stepSettings.collaborationMode?.mode, .plan)
        XCTAssertNil(sess.activeTurn)
    }

    func testSuspendTurnAndShutdownStopsWithoutATerminalTurnEvent() async throws {
        let sess = Session()
        let entered = expectation(description: "sampling")
        let gate = SubmissionAck()
        sess.runSamplingOverride = { _, _ in
            entered.fulfill()
            await gate.wait()
            return SamplingRequestResult(needsFollowUp: false, lastAgentMessage: "should-not-finish")
        }
        _ = try await sess.submit(
            .userInput(TurnInputBuilder.user([.text(text: "hello", textElements: [])]))
        )
        await fulfillment(of: [entered], timeout: 1)
        let turnId = try XCTUnwrap(sess.activeTurn?.task?.turnContext.subId)
        let suspendedTurn = sess.activeTurn
        suspendedTurn?.turnState.pendingInput.enqueue(
            TurnInputBuilder.user([.text(text: "queued", textElements: [])])
        )
        _ = try await sess.submit(.suspendTurnAndShutdown)
        XCTAssertTrue(suspendedTurn?.turnState.pendingInput.isEmpty == true)
        XCTAssertEqual(sess.lastSuspendTurnOutcome, .suspended(turnId: turnId))
        XCTAssertNil(sess.lastSuspendTurnError)
        XCTAssertNil(sess.activeTurn)
        XCTAssertNil(sess.lastTurnAbortReason)
        XCTAssertEqual(sess.lastStartedTurnId, turnId)
        XCTAssertTrue(sess.state.shuttingDown)
        XCTAssertFalse(sess.emittedEvents.contains { event in
            if case .turnAborted = event { return true }
            if case .turnComplete = event { return true }
            return false
        })
        XCTAssertTrue(sess.emittedEvents.contains { event in
            if case .shutdownComplete = event { return true }
            return false
        })
        gate.signal()
    }

    func testSuspendTurnAndShutdownRejectsIdleReviewAndDescendants() async throws {
        let sess = Session()
        _ = try await sess.submit(.suspendTurnAndShutdown)
        XCTAssertEqual(sess.lastSuspendTurnOutcome, .notActive)
        XCTAssertFalse(sess.state.shuttingDown)

        let entered = expectation(description: "review sampling")
        let gate = SubmissionAck()
        sess.runSamplingOverride = { _, _ in
            entered.fulfill()
            await gate.wait()
            return SamplingRequestResult(needsFollowUp: false, lastAgentMessage: "review")
        }
        _ = try await sess.submit(
            .review(ReviewRequest(target: .custom(instructions: "Check the parser")))
        )
        await fulfillment(of: [entered], timeout: 1)
        _ = try await sess.submit(.suspendTurnAndShutdown)
        XCTAssertEqual(sess.lastSuspendTurnOutcome, .unsupportedTask)
        XCTAssertEqual(sess.activeTurn?.task?.kind, .review)
        XCTAssertFalse(sess.state.shuttingDown)
        gate.signal()
        await sess.waitUntilIdle()

        let regularEntered = expectation(description: "regular sampling")
        let regularGate = SubmissionAck()
        sess.runSamplingOverride = { _, _ in
            regularEntered.fulfill()
            await regularGate.wait()
            return SamplingRequestResult(needsFollowUp: false, lastAgentMessage: "kept")
        }
        _ = try await sess.submit(
            .userInput(TurnInputBuilder.user([.text(text: "hello", textElements: [])]))
        )
        await fulfillment(of: [regularEntered], timeout: 1)
        sess.services.liveAgentSubtreeCount = 2
        _ = try await sess.submit(.suspendTurnAndShutdown)
        XCTAssertEqual(sess.lastSuspendTurnOutcome, .hasLiveDescendants)
        XCTAssertNotNil(sess.activeTurn)
        XCTAssertFalse(sess.state.shuttingDown)

        sess.state.sessionConfiguration.sessionSource = .internal(.guardian)
        _ = try await sess.submit(.suspendTurnAndShutdown)
        XCTAssertNil(sess.lastSuspendTurnOutcome)
        XCTAssertEqual(
            sess.lastSuspendTurnError,
            "turn suspension requires the owning root thread"
        )
        XCTAssertNotNil(sess.activeTurn)
        XCTAssertFalse(sess.emittedEvents.contains { event in
            if case .shutdownComplete = event { return true }
            if case .turnAborted = event { return true }
            return false
        })
        regularGate.signal()
        await sess.waitUntilIdle()
    }

    func testUserInputAnswerResumesTheWaitingTurn() async throws {
        let sess = Session()
        let entered = expectation(description: "sampling")
        let gate = SubmissionAck()
        defer {
            sess.activeTurn?.turnState.clearPendingWaiters()
            gate.signal()
        }
        sess.runSamplingOverride = { _, _ in
            entered.fulfill()
            await gate.wait()
            return SamplingRequestResult(needsFollowUp: false, lastAgentMessage: "kept")
        }
        _ = try await sess.submit(
            .userInput(TurnInputBuilder.user([.text(text: "hello", textElements: [])]))
        )
        await fulfillment(of: [entered], timeout: 1)
        let turn = try XCTUnwrap(sess.activeTurn?.task?.turnContext)
        let started = sess.emittedEvents.filter { event in
            if case .turnStarted = event { return true }
            return false
        }.count
        let question = RequestUserInputQuestion(id: "q1", header: "Color", question: "Pick one")
        let args = RequestUserInputArgs(questions: [question], isBlocking: true)
        let response = RequestUserInputResponse(
            answers: ["q1": RequestUserInputAnswer(answers: ["blue"])]
        )

        let first = Task { await sess.requestUserInput(turnContext: turn, callId: "call-1", args: args) }
        try await waitUntil {
            sess.emittedEvents.contains { event in
                if case .requestUserInput(let requested) = event {
                    return requested.callId == "call-1" && requested.turnId == turn.subId
                }
                return false
            }
        }
        let second = Task { await sess.requestUserInput(turnContext: turn, callId: "call-2", args: args) }
        try await waitUntil {
            sess.emittedEvents.contains { event in
                if case .requestUserInput(let requested) = event {
                    return requested.callId == "call-2"
                }
                return false
            }
        }
        let replaced = await first.value
        XCTAssertNil(replaced)

        _ = try await sess.submit(.userInputAnswer(id: "missing", response: response))
        XCTAssertEqual(sess.activeTurn?.task?.turnContext.subId, turn.subId)
        _ = try await sess.submit(.userInputAnswer(id: turn.subId, response: response))
        let accepted = await second.value
        XCTAssertEqual(accepted?.response, response)
        XCTAssertEqual(accepted?.acceptanceOrder, 0)
        XCTAssertEqual(
            sess.emittedEvents.filter { event in
                if case .turnStarted = event { return true }
                return false
            }.count,
            started
        )

        sess.state.history.guardianReviewMode = .legacy
        let legacy = Task { await sess.requestUserInput(turnContext: turn, callId: "call-3", args: args) }
        try await waitUntil {
            sess.emittedEvents.contains { event in
                if case .requestUserInput(let requested) = event {
                    return requested.callId == "call-3"
                }
                return false
            }
        }
        _ = try await sess.submit(.userInputAnswer(id: turn.subId, response: response))
        let legacyAccepted = await legacy.value
        XCTAssertEqual(legacyAccepted?.response, response)
        XCTAssertNil(legacyAccepted?.acceptanceOrder)
        XCTAssertEqual(sess.activeTurn?.task?.turnContext.subId, turn.subId)
        gate.signal()
        await sess.waitUntilIdle()
        XCTAssertEqual(sess.lastTaskAgentMessage, "kept")
    }

    func testUserInputAnswerDoesNothingWhenNobodyIsWaiting() async throws {
        let sess = Session()
        let response = RequestUserInputResponse(
            answers: ["q1": RequestUserInputAnswer(answers: ["blue"])]
        )
        _ = try await sess.submit(.userInputAnswer(id: "missing", response: response))
        XCTAssertNil(sess.activeTurn)
        XCTAssertNil(sess.lastStartedTurnId)
        XCTAssertFalse(sess.emittedEvents.contains { event in
            if case .turnStarted = event { return true }
            return false
        })
    }

    func testRequestUserInputToolWaitsForUserInputAnswer() async throws {
        let sess = Session()
        let entered = expectation(description: "sampling")
        let gate = SubmissionAck()
        defer {
            sess.activeTurn?.turnState.clearPendingWaiters()
            gate.signal()
        }
        sess.runSamplingOverride = { _, _ in
            entered.fulfill()
            await gate.wait()
            return SamplingRequestResult(needsFollowUp: false, lastAgentMessage: "kept")
        }
        _ = try await sess.submit(
            .userInput(TurnInputBuilder.user([.text(text: "hello", textElements: [])]))
        )
        await fulfillment(of: [entered], timeout: 1)
        let live = try XCTUnwrap(sess.activeTurn?.task?.turnContext)
        let started = sess.emittedEvents.filter { event in
            if case .turnStarted = event { return true }
            return false
        }.count
        let toolTurn = TurnContext(subId: live.subId, sessionSource: live.sessionSource)
        toolTurn.collaborationMode = CollaborationMode(
            mode: .plan,
            settings: CodexProtocol.Settings(model: live.model)
        )
        let step = StepContext(turn: toolTurn)
        _ = assembleToolRouter(sess: sess, stepContext: step)
        let arguments = """
        {"questions":[{"id":"q1","header":"Color","question":"Pick one","options":[{"label":"Blue","description":"Use blue"}]}]}
        """
        let outputTask = Task {
            try await ToolCallRuntime(session: sess, stepContext: step).handleToolCall(
                ToolCall(
                    toolName: ToolName(plain: REQUEST_USER_INPUT_TOOL_NAME),
                    callId: "call-ui",
                    payload: .function(arguments: arguments)
                ),
                cancellationToken: CancellationToken()
            )
        }
        try await waitUntil {
            sess.emittedEvents.contains { event in
                if case .requestUserInput(let requested) = event {
                    return requested.callId == "call-ui"
                        && requested.turnId == live.subId
                        && requested.isBlocking
                }
                return false
            }
        }
        let response = RequestUserInputResponse(
            answers: ["q1": RequestUserInputAnswer(answers: ["blue"])]
        )
        _ = try await sess.submit(.userInputAnswer(id: live.subId, response: response))
        let output = try await outputTask.value
        guard case .functionCallOutput(_, let callId, _, _, let payload, _) = output else {
            return XCTFail("expected function call output")
        }
        XCTAssertEqual(callId, "call-ui")
        XCTAssertEqual(payload.body.toText()?.contains("blue"), true)
        XCTAssertEqual(
            sess.emittedEvents.filter { event in
                if case .turnStarted = event { return true }
                return false
            }.count,
            started
        )
        XCTAssertEqual(sess.activeTurn?.task?.turnContext.subId, live.subId)
        gate.signal()
        await sess.waitUntilIdle()
        XCTAssertEqual(sess.lastTaskAgentMessage, "kept")
        XCTAssertEqual(sess.lastStartedTurnId, live.subId)
        XCTAssertTrue(sess.state.history.verifiedAnswers.isEmpty)
    }

    func testRequestUserInputRecordsAVerifiedAnswer() async throws {
        let sess = Session()
        let turn = TurnContext()
        turn.config.features.enable(.guardianApproval)
        let question = RequestUserInputQuestion(
            id: "pick_one",
            header: "Hdr",
            question: "Pick one",
            options: [
                RequestUserInputQuestionOption(label: "A", description: "Use A"),
                RequestUserInputQuestionOption(label: "B", description: "Use B"),
            ]
        )
        func record(_ answers: [String: [String]], order: UInt64? = 0) async {
            await sess.recordRetainedVerifiedAnswer(
                turnContext: turn,
                callId: "call-direct",
                questions: [question],
                response: RequestUserInputResponse(
                    answers: answers.mapValues { RequestUserInputAnswer(answers: $0) }
                ),
                acceptanceOrder: order
            )
        }
        await record(["pick_one": [" "]])
        await record(["other": ["A"]])
        XCTAssertTrue(sess.state.history.verifiedAnswers.isEmpty)
        XCTAssertEqual(sess.state.history.userMessageRevision, 0)

        sess.state.history.guardianReviewMode = .legacy
        await record(["pick_one": ["A"]])
        XCTAssertTrue(sess.state.history.verifiedAnswers.isEmpty)
        sess.state.history.guardianReviewMode = .threadOwned

        turn.config.features.disable(.guardianApproval)
        await record(["pick_one": ["A"]])
        XCTAssertTrue(sess.state.history.verifiedAnswers.isEmpty)
        turn.config.features.enable(.guardianApproval)

        let entered = expectation(description: "sampling")
        let gate = SubmissionAck()
        defer {
            sess.activeTurn?.turnState.clearPendingWaiters()
            gate.signal()
        }
        sess.runSamplingOverride = { _, _ in
            entered.fulfill()
            await gate.wait()
            return SamplingRequestResult(needsFollowUp: false, lastAgentMessage: "kept")
        }
        _ = try await sess.submit(
            .userInput(TurnInputBuilder.user([.text(text: "hello", textElements: [])]))
        )
        await fulfillment(of: [entered], timeout: 1)
        let live = try XCTUnwrap(sess.activeTurn?.task?.turnContext)
        let revision = sess.state.history.userMessageRevision
        let toolTurn = TurnContext(subId: live.subId, sessionSource: live.sessionSource)
        toolTurn.config.features.enable(.guardianApproval)
        toolTurn.collaborationMode = CollaborationMode(
            mode: .plan,
            settings: CodexProtocol.Settings(model: live.model)
        )
        let step = StepContext(turn: toolTurn)
        _ = assembleToolRouter(sess: sess, stepContext: step)
        let arguments = """
        {"questions":[{"id":"q1","header":"Color","question":"Pick one","options":[{"label":"Blue","description":"Use blue"},{"label":"Red","description":"Use red"}]}]}
        """
        let outputTask = Task {
            try await ToolCallRuntime(session: sess, stepContext: step).handleToolCall(
                ToolCall(
                    toolName: ToolName(plain: REQUEST_USER_INPUT_TOOL_NAME),
                    callId: "call-ui",
                    payload: .function(arguments: arguments)
                ),
                cancellationToken: CancellationToken()
            )
        }
        try await waitUntil {
            sess.emittedEvents.contains { event in
                if case .requestUserInput(let requested) = event {
                    return requested.callId == "call-ui" && requested.turnId == live.subId
                }
                return false
            }
        }
        _ = try await sess.submit(
            .userInputAnswer(
                id: live.subId,
                response: RequestUserInputResponse(
                    answers: ["q1": RequestUserInputAnswer(answers: ["Blue"])]
                )
            )
        )
        let output = try await outputTask.value
        guard case .functionCallOutput(_, _, _, _, let payload, _) = output else {
            return XCTFail("expected function call output")
        }
        XCTAssertEqual(payload.body.toText()?.contains("Blue"), true)
        let recorded = try XCTUnwrap(
            sess.state.history.verifiedAnswers.first { $0.callId == "call-ui" }
        )
        XCTAssertEqual(recorded.turnId, live.subId)
        XCTAssertEqual(recorded.acceptanceOrder, 0)
        XCTAssertEqual(
            recorded.questions,
            [RetainedVerifiedQuestion(question: "Pick one\nBlue: Use blue", answer: "Blue")]
        )
        XCTAssertEqual(sess.state.history.userMessageRevision, revision + 1)
        XCTAssertTrue(sess.state.history.verifiedAnswersComplete())

        await record(["pick_one": [String(repeating: "x", count: 20_000)]])
        XCTAssertEqual(
            sess.state.history.verifiedAnswers.first { $0.callId == "call-direct" }?.questions.isEmpty,
            true
        )
        XCTAssertFalse(sess.state.history.verifiedAnswersComplete())
        XCTAssertEqual(sess.state.history.userMessageRevision, revision + 2)
        await record(["pick_one": [String(repeating: "x", count: 20_000)]])
        XCTAssertEqual(sess.state.history.userMessageRevision, revision + 2)

        gate.signal()
        await sess.waitUntilIdle()
    }

    func testVerifiedAnswerPersistsToTheRollout() async throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("sage-rollout-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let quiet = Session()
        quiet.state.sessionConfiguration.codexHome = home.path
        let turn = TurnContext()
        turn.config.features.enable(.guardianApproval)
        let question = RequestUserInputQuestion(
            id: "pick_one", header: "Hdr", question: "Pick one", options: nil
        )
        let response = RequestUserInputResponse(
            answers: ["pick_one": RequestUserInputAnswer(answers: ["yes"])]
        )
        await quiet.recordRetainedVerifiedAnswer(
            turnContext: turn,
            callId: "call-roll",
            questions: [question],
            response: response,
            acceptanceOrder: 4
        )
        XCTAssertNil(quiet.persistedRolloutPath())
        XCTAssertEqual(quiet.state.history.verifiedAnswers.count, 1)

        let sess = Session()
        sess.state.sessionConfiguration.codexHome = home.path
        sess.enableRolloutPersistence()
        await sess.recordRetainedVerifiedAnswer(
            turnContext: turn,
            callId: "call-roll",
            questions: [question],
            response: response,
            acceptanceOrder: 4
        )
        let path = try XCTUnwrap(sess.persistedRolloutPath())
        let stored = try RolloutRecorder.loadRolloutItems(path: path).items.compactMap(verifiedAnswer(from:))
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored[0].turnId, turn.subId)
        XCTAssertEqual(stored[0].callId, "call-roll")
        XCTAssertEqual(stored[0].acceptanceOrder, 4)
        XCTAssertEqual(
            stored[0].questions,
            [RetainedVerifiedQuestion(question: "Pick one", answer: "yes")]
        )
        let restored = ContextManager()
        XCTAssertNotNil(restored.recordVerifiedAnswer(stored[0]))
        XCTAssertEqual(restored.verifiedAnswers, sess.state.history.verifiedAnswers)
        XCTAssertNil(restored.recordVerifiedAnswer(stored[0]))

        await sess.recordRetainedVerifiedAnswer(
            turnContext: turn,
            callId: "call-roll",
            questions: [question],
            response: response,
            acceptanceOrder: 4
        )
        let repeated = try RolloutRecorder.loadRolloutItems(path: path).items.compactMap(verifiedAnswer(from:))
        XCTAssertEqual(repeated.count, 1)

        await sess.recordRetainedVerifiedAnswer(
            turnContext: turn,
            callId: "call-huge",
            questions: [question],
            response: RequestUserInputResponse(
                answers: ["pick_one": RequestUserInputAnswer(answers: [String(repeating: "x", count: 20_000)])]
            ),
            acceptanceOrder: 5
        )
        let bounded = try RolloutRecorder.loadRolloutItems(path: path).items.compactMap(verifiedAnswer(from:))
        XCTAssertEqual(bounded.count, 2)
        XCTAssertEqual(bounded[1].questions, [])
        XCTAssertEqual(bounded[1].acceptanceOrder, 5)
        await sess.recordRetainedVerifiedAnswer(
            turnContext: turn,
            callId: "call-huge",
            questions: [question],
            response: RequestUserInputResponse(
                answers: ["pick_one": RequestUserInputAnswer(answers: [String(repeating: "x", count: 20_000)])]
            ),
            acceptanceOrder: 5
        )
        let stillBounded = try RolloutRecorder.loadRolloutItems(path: path).items.compactMap(verifiedAnswer(from:))
        XCTAssertEqual(stillBounded.count, 2)
    }

    func testRolloutReconstructionRestoresVerifiedAnswers() async throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("sage-restore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let turn = TurnContext()
        turn.config.features.enable(.guardianApproval)
        let question = RequestUserInputQuestion(
            id: "pick_one", header: "Hdr", question: "Pick one", options: nil
        )
        let first = Session()
        first.state.sessionConfiguration.codexHome = home.path
        first.enableRolloutPersistence()
        await first.recordRetainedVerifiedAnswer(
            turnContext: turn,
            callId: "call-roll",
            questions: [question],
            response: RequestUserInputResponse(
                answers: ["pick_one": RequestUserInputAnswer(answers: ["yes"])]
            ),
            acceptanceOrder: 4
        )
        let path = try XCTUnwrap(first.persistedRolloutPath())
        let restored = Session()
        restored.restoreVerifiedAnswers(fromRolloutPath: path)
        XCTAssertEqual(restored.state.history.verifiedAnswers, first.state.history.verifiedAnswers)
        XCTAssertEqual(restored.state.history.userMessageRevision, 1)
        XCTAssertTrue(restored.state.history.verifiedAnswersComplete())
        restored.state.sessionConfiguration.codexHome = home.path
        restored.resumeRolloutPersistence(path: path)
        await restored.recordRetainedVerifiedAnswer(
            turnContext: turn,
            callId: "call-next",
            questions: [question],
            response: RequestUserInputResponse(
                answers: ["pick_one": RequestUserInputAnswer(answers: ["later"])]
            ),
            acceptanceOrder: 5
        )
        XCTAssertEqual(restored.persistedRolloutPath(), path)
        let appended = try RolloutRecorder.loadRolloutItems(path: path).items.compactMap(verifiedAnswer(from:))
        XCTAssertEqual(appended.map(\.callId), ["call-roll", "call-next"])

        let earlier = verifiedAnswerRolloutItem(
            RetainedVerifiedAnswer(
                turnId: "old-turn",
                callId: "before",
                questions: [RetainedVerifiedQuestion(question: "Q", answer: "old")],
                acceptanceOrder: 1
            )
        )
        let later = verifiedAnswerRolloutItem(
            RetainedVerifiedAnswer(
                turnId: "new-turn",
                callId: "after",
                questions: [RetainedVerifiedQuestion(question: "Q", answer: "new")],
                acceptanceOrder: 2
            )
        )
        var bounded = CompactedItem(message: "summary")
        bounded.replacementHistory = []
        bounded.windowNumber = 1
        bounded.resumeMetadata = .object([:])
        bounded.retainedContext = .object([
            "incomplete": .bool(true),
            "verified_answers": .array([
                .object([
                    "turn_id": .string("kept-turn"),
                    "call_id": .string("checkpoint"),
                    "order": .uint(3),
                    "questions": .array([
                        .object([
                            "question": .string("Q"),
                            "answer": .string("kept"),
                        ]),
                    ]),
                ]),
            ]),
        ])
        let history = ContextManager()
        RolloutReconstruction.restoreVerifiedAnswers(
            from: [earlier, .compacted(bounded), later],
            into: history
        )
        XCTAssertEqual(history.verifiedAnswers.map(\.callId), ["checkpoint", "after"])
        XCTAssertEqual(history.verifiedAnswers[0].acceptanceOrder, 3)
        XCTAssertFalse(history.verifiedAnswersComplete())
        XCTAssertEqual(history.userMessageRevision, 2)

        let unbounded = ContextManager()
        var openCompaction = CompactedItem(message: "summary")
        openCompaction.replacementHistory = []
        openCompaction.windowNumber = 1
        RolloutReconstruction.restoreVerifiedAnswers(
            from: [earlier, .compacted(openCompaction), later],
            into: unbounded
        )
        XCTAssertEqual(unbounded.verifiedAnswers.map(\.callId), ["before", "after"])
    }

    func testRolloutReconstructionRestoresResponseItems() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("sage-restore-items-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let recorder = try RolloutRecorder.create(
            config: RolloutConfig(codexHome: home.path),
            params: .new(conversationId: ThreadId(), source: .cli, originator: "sage-test")
        )
        try recorder.recordItems([
            rolloutMessage("user", "before"),
            rolloutMessage("system", "hidden"),
            .responseItem(CodexHistory.ResponseItemEnvelope(item: .compactionTrigger)),
            rolloutMessage("assistant", "after"),
        ])
        try recorder.flush()
        let restored = Session()
        restored.restoreVerifiedAnswers(fromRolloutPath: recorder.rolloutPath)
        XCTAssertEqual(rolloutMessageTexts(restored.state.history), ["before", "after"])
        XCTAssertEqual(restored.state.history.userMessageRevision, 1)

        var bounded = CompactedItem(message: "summary")
        bounded.replacementHistory = [
            CodexHistory.ResponseItemEnvelope(item: rolloutTextMessage("user", "kept-summary"))
        ]
        bounded.windowNumber = 1
        bounded.resumeMetadata = .object([:])
        let history = ContextManager()
        RolloutReconstruction.restoreVerifiedAnswers(
            from: [
                rolloutMessage("user", "before"),
                rolloutMessage("system", "hidden"),
                .compacted(bounded),
                rolloutMessage("assistant", "after"),
                .responseItem(CodexHistory.ResponseItemEnvelope(item: .compactionTrigger)),
            ],
            into: history
        )
        XCTAssertEqual(rolloutMessageTexts(history), ["kept-summary", "after"])
        XCTAssertEqual(history.userMessageRevision, 1)
    }

    func testRolloutReconstructionTruncatesFunctionOutputs() {
        let original = String(repeating: "x", count: 400)
        let policy = TruncationPolicy.bytes(16)
        let output = rolloutFunctionOutput(original)
        var limited = CodexHarnessMetadata()
        limited.historyTruncationTokenLimit = 4
        let custom = RolloutItem.responseItem(
            CodexHistory.ResponseItemEnvelope(
                item: .customToolCallOutput(
                    id: nil,
                    callId: "call-2",
                    name: "tool",
                    output: .fromText(original),
                    internalChatMessageMetadataPassthrough: nil
                ),
                metadata: limited
            )
        )
        let history = ContextManager()
        RolloutReconstruction.restoreVerifiedAnswers(
            from: [output, custom, rolloutFunctionOutput("ok")],
            into: history,
            truncationPolicy: policy
        )
        let texts = restoredOutputTexts(history)
        XCTAssertEqual(texts[0], truncateText(original, policy: withSerializationAllowance(policy)))
        XCTAssertEqual(texts[1], truncateText(original, policy: .tokens(4)))
        XCTAssertEqual(texts[2], "ok")
        XCTAssertNotEqual(texts[0], original)

        var bounded = CompactedItem(message: "summary")
        bounded.replacementHistory = [
            CodexHistory.ResponseItemEnvelope(item: .functionCallOutput(
                id: nil,
                callId: "kept",
                name: "shell",
                namespace: nil,
                output: .fromText(original),
                internalChatMessageMetadataPassthrough: nil
            ))
        ]
        bounded.windowNumber = 1
        bounded.resumeMetadata = .object([:])
        let replaced = ContextManager()
        RolloutReconstruction.restoreVerifiedAnswers(
            from: [.compacted(bounded), output],
            into: replaced,
            truncationPolicy: policy
        )
        XCTAssertEqual(
            restoredOutputTexts(replaced),
            [original, truncateText(original, policy: withSerializationAllowance(policy))]
        )
    }

    func testRolloutReconstructionDropsRolledBackUserTurns() {
        func user(_ text: String, turn: String) -> RolloutItem {
            .responseItem(CodexHistory.ResponseItemEnvelope(item: .message(
                id: nil,
                role: "user",
                content: [.inputText(text: text)],
                phase: nil,
                internalChatMessageMetadataPassthrough: InternalChatMessageMetadataPassthrough(turnId: turn)
            )))
        }
        func answer(_ turn: String, _ call: String) -> RolloutItem {
            verifiedAnswerRolloutItem(
                RetainedVerifiedAnswer(
                    turnId: turn,
                    callId: call,
                    questions: [RetainedVerifiedQuestion(question: "Q", answer: call)],
                    acceptanceOrder: 1
                )
            )
        }

        let history = ContextManager()
        RolloutReconstruction.restoreVerifiedAnswers(
            from: [
                user("keep", turn: "turn-a"),
                rolloutMessage("assistant", "reply"),
                answer("turn-a", "kept"),
                user("drop", turn: "turn-b"),
                rolloutMessage("assistant", "gone"),
                answer("turn-b", "dropped"),
                .eventMsg(.threadRolledBack(ThreadRolledBackEvent(numTurns: 1))),
                user("after", turn: "turn-c"),
            ],
            into: history
        )
        XCTAssertEqual(rolloutMessageTexts(history), ["keep", "reply", "after"])
        XCTAssertEqual(history.verifiedAnswers.map(\.callId), ["kept"])
        XCTAssertEqual(history.userMessageRevision, 6)

        let unchanged = ContextManager()
        RolloutReconstruction.restoreVerifiedAnswers(
            from: [
                user("stay", turn: "turn-a"),
                .eventMsg(.threadRolledBack(ThreadRolledBackEvent(numTurns: 0))),
            ],
            into: unchanged
        )
        XCTAssertEqual(rolloutMessageTexts(unchanged), ["stay"])
        XCTAssertEqual(unchanged.userMessageRevision, 1)

        let prefix = ContextManager()
        RolloutReconstruction.restoreVerifiedAnswers(
            from: [
                rolloutMessage("assistant", "pre"),
                user("gone", turn: "turn-a"),
                rolloutMessage("assistant", "post"),
                .eventMsg(.threadRolledBack(ThreadRolledBackEvent(numTurns: 99))),
            ],
            into: prefix
        )
        XCTAssertEqual(rolloutMessageTexts(prefix), ["pre"])
        XCTAssertEqual(prefix.userMessageRevision, 2)
    }

    func testRolloutReconstructionRebuildsLegacyCompaction() {
        let taskId = ResponseItemId.fromServer("msg_task")
        func task(_ text: String) -> RolloutItem {
            .responseItem(CodexHistory.ResponseItemEnvelope(item: .message(
                id: taskId,
                role: "user",
                content: [.inputText(text: text)],
                phase: nil,
                internalChatMessageMetadataPassthrough: nil
            )))
        }
        let history = ContextManager()
        RolloutReconstruction.restoreVerifiedAnswers(
            from: [
                task("task"),
                rolloutMessage("assistant", "work"),
                verifiedAnswerRolloutItem(
                    RetainedVerifiedAnswer(
                        turnId: "turn-a",
                        callId: "kept",
                        questions: [RetainedVerifiedQuestion(question: "Q", answer: "yes")],
                        acceptanceOrder: 1
                    )
                ),
                .compacted(CompactedItem(message: "first summary")),
                rolloutMessage("user", "follow"),
                .compacted(CompactedItem(message: "second summary")),
            ],
            into: history
        )
        XCTAssertEqual(rolloutMessageTexts(history), ["task", "follow", "second summary"])
        XCTAssertEqual(history.items[0].item.id()?.asStr, "msg_task")
        XCTAssertEqual(history.verifiedAnswers.map(\.callId), ["kept"])
        XCTAssertEqual(history.userMessageRevision, 5)
        guard case .message(_, _, _, _, let summary) = history.items[2].item else {
            return XCTFail("expected the rebuilt summary")
        }
        XCTAssertEqual(
            summary?.contentItemKinds,
            [ContentItemKind("compaction.summary")]
        )

        let empty = ContextManager()
        RolloutReconstruction.restoreVerifiedAnswers(
            from: [.compacted(CompactedItem(message: ""))],
            into: empty
        )
        XCTAssertEqual(rolloutMessageTexts(empty), ["(no summary available)"])
        XCTAssertEqual(empty.userMessageRevision, 1)

        let cleared = ContextManager()
        cleared.guardianReviewMode = .legacy
        RolloutReconstruction.restoreVerifiedAnswers(
            from: [task("task"), .compacted(CompactedItem(message: "summary"))],
            into: cleared
        )
        XCTAssertNil(cleared.items[0].item.id())

        var current = CompactedItem(message: "ignored")
        current.replacementHistory = []
        let kept = ContextManager()
        RolloutReconstruction.restoreVerifiedAnswers(
            from: [
                task("task"),
                rolloutMessage("assistant", "work"),
                .compacted(current),
                rolloutMessage("user", "follow"),
            ],
            into: kept
        )
        XCTAssertEqual(rolloutMessageTexts(kept), ["task", "work", "follow"])
        XCTAssertEqual(kept.userMessageRevision, 2)
    }

    func testRolloutReconstructionSkipsRolledBackCompactionCheckpoints() {
        func bounded(_ summary: String, _ window: UInt64) -> RolloutItem {
            var item = CompactedItem(message: summary)
            item.replacementHistory = [
                CodexHistory.ResponseItemEnvelope(item: rolloutTextMessage("user", summary))
            ]
            item.windowNumber = window
            item.resumeMetadata = .object([:])
            return .compacted(item)
        }
        func turn(_ id: String, _ body: String, _ compaction: RolloutItem) -> [RolloutItem] {
            [
                .eventMsg(.turnStarted(TurnStartedEvent(turnId: id))),
                .eventMsg(.userMessage(UserMessageEvent(message: body))),
                rolloutMessage("user", body),
                compaction,
                .eventMsg(.turnComplete(TurnCompleteEvent(turnId: id))),
            ]
        }

        let history = ContextManager()
        RolloutReconstruction.restoreVerifiedAnswers(
            from: turn("keep", "keep-body", bounded("kept-summary", 1))
                + turn("drop", "drop-body", bounded("dropped-summary", 2))
                + [
                    .eventMsg(.threadRolledBack(ThreadRolledBackEvent(numTurns: 1))),
                    rolloutMessage("user", "after"),
                ],
            into: history
        )
        XCTAssertEqual(rolloutMessageTexts(history), ["kept-summary", "after"])
        XCTAssertEqual(history.userMessageRevision, 4)

        let droppedOnly = ContextManager()
        RolloutReconstruction.restoreVerifiedAnswers(
            from: [
                .eventMsg(.turnStarted(TurnStartedEvent(turnId: "keep"))),
                rolloutMessage("user", "keep"),
                .eventMsg(.turnComplete(TurnCompleteEvent(turnId: "keep"))),
                .eventMsg(.turnStarted(TurnStartedEvent(turnId: "drop"))),
                rolloutMessage("user", "drop"),
                bounded("dropped-summary", 1),
                .eventMsg(.turnComplete(TurnCompleteEvent(turnId: "drop"))),
                .eventMsg(.threadRolledBack(ThreadRolledBackEvent(numTurns: 1))),
            ],
            into: droppedOnly
        )
        XCTAssertEqual(rolloutMessageTexts(droppedOnly), ["keep"])

        let newest = ContextManager()
        RolloutReconstruction.restoreVerifiedAnswers(
            from: turn("keep", "keep-body", bounded("kept-summary", 1))
                + turn("drop", "drop-body", bounded("dropped-summary", 2)),
            into: newest
        )
        XCTAssertEqual(rolloutMessageTexts(newest), ["dropped-summary"])

        var incomplete = CompactedItem(message: "new")
        incomplete.replacementHistory = [
            CodexHistory.ResponseItemEnvelope(item: rolloutTextMessage("user", "new-summary"))
        ]
        incomplete.windowNumber = 2
        let blocked = ContextManager()
        RolloutReconstruction.restoreVerifiedAnswers(
            from: [
                rolloutMessage("user", "before"),
                bounded("kept-summary", 1),
                rolloutMessage("user", "middle"),
                .compacted(incomplete),
            ],
            into: blocked
        )
        XCTAssertEqual(rolloutMessageTexts(blocked), ["before", "middle"])
    }

    func testRolloutReconstructionReplaysWorldState() {
        let history = ContextManager()
        RolloutReconstruction.restoreVerifiedAnswers(
            from: [
                .worldState(.full([
                    "environment": .object(["status": .string("old")]),
                ])),
                .compacted(CompactedItem(message: "reset")),
                .worldState(.full([
                    "environment": .object([
                        "status": .string("starting"),
                        "cwd": .string("/workspace"),
                    ]),
                ])),
                .worldState(WorldStateItem(full: false, state: [
                    "environment": .object(["status": .string("ready")]),
                ])),
            ],
            into: history
        )
        XCTAssertEqual(
            history.worldStateBaseline?.jsonSections["environment"],
            .object([
                "status": .string("ready"),
                "cwd": .string("/workspace"),
            ])
        )

        let ignored = ContextManager()
        RolloutReconstruction.restoreVerifiedAnswers(
            from: [
                .worldState(.full([
                    "environment": .object(["status": .string("old")]),
                ])),
                .compacted(CompactedItem(message: "reset")),
                .worldState(WorldStateItem(full: false, state: [
                    "environment": .object(["status": .string("ready")]),
                ])),
            ],
            into: ignored
        )
        XCTAssertNil(ignored.worldStateBaseline)

        let rolledBack = ContextManager()
        RolloutReconstruction.restoreVerifiedAnswers(
            from: [
                .eventMsg(.turnStarted(TurnStartedEvent(turnId: "keep"))),
                .worldState(.full([
                    "environment": .object(["status": .string("kept")]),
                ])),
                .eventMsg(.turnComplete(TurnCompleteEvent(turnId: "keep"))),
                .eventMsg(.turnStarted(TurnStartedEvent(turnId: "drop"))),
                .eventMsg(.userMessage(UserMessageEvent(message: "drop"))),
                .worldState(.full([
                    "environment": .object(["status": .string("dropped")]),
                ])),
                .eventMsg(.turnComplete(TurnCompleteEvent(turnId: "drop"))),
                .eventMsg(.threadRolledBack(ThreadRolledBackEvent(numTurns: 1))),
            ],
            into: rolledBack
        )
        XCTAssertEqual(
            rolledBack.worldStateBaseline?.jsonSections["environment"],
            .object(["status": .string("kept")])
        )
    }

    func testRolloutReconstructionRestoresReferenceContext() {
        func context(_ turn: String, _ model: String) -> RolloutItem {
            .turnContext(TurnContextItem(turnId: turn, cwd: "/workspace", model: model))
        }
        func userTurn(_ id: String, _ model: String, compactionBeforeContext: Bool) -> [RolloutItem] {
            var items: [RolloutItem] = [
                .eventMsg(.turnStarted(TurnStartedEvent(turnId: id))),
                .eventMsg(.userMessage(UserMessageEvent(message: id))),
            ]
            var compaction = CompactedItem(message: "summary")
            compaction.replacementHistory = []
            if compactionBeforeContext {
                items.append(.compacted(compaction))
            }
            items.append(context(id, model))
            if !compactionBeforeContext {
                items.append(.compacted(compaction))
            }
            items.append(.eventMsg(.turnComplete(TurnCompleteEvent(turnId: id))))
            return items
        }

        let restored = ContextManager()
        RolloutReconstruction.restoreVerifiedAnswers(
            from: userTurn("keep", "restored-model", compactionBeforeContext: true),
            into: restored
        )
        XCTAssertEqual(restored.referenceContextItemValue()?.model, "restored-model")

        let cleared = ContextManager()
        RolloutReconstruction.restoreVerifiedAnswers(
            from: userTurn("keep", "cleared-model", compactionBeforeContext: false),
            into: cleared
        )
        XCTAssertNil(cleared.referenceContextItemValue())

        let rolledBack = ContextManager()
        RolloutReconstruction.restoreVerifiedAnswers(
            from: userTurn("keep", "kept-model", compactionBeforeContext: true)
                + userTurn("drop", "dropped-model", compactionBeforeContext: true)
                + [.eventMsg(.threadRolledBack(ThreadRolledBackEvent(numTurns: 1)))],
            into: rolledBack
        )
        XCTAssertEqual(rolledBack.referenceContextItemValue()?.model, "kept-model")

        let legacy = ContextManager()
        RolloutReconstruction.restoreVerifiedAnswers(
            from: [
                rolloutMessage("user", "before"),
                .compacted(CompactedItem(message: "legacy summary")),
            ] + userTurn("later", "later-model", compactionBeforeContext: true),
            into: legacy
        )
        XCTAssertNil(legacy.referenceContextItemValue())

        let fromSnapshot = ContextManager()
        RolloutReconstruction.restoreVerifiedAnswers(
            from: [
                .worldState(.full([
                    "environment": .object(["status": .string("ready")]),
                ])),
                context("solo", "from-snapshot"),
            ],
            into: fromSnapshot
        )
        XCTAssertEqual(fromSnapshot.referenceContextItemValue()?.model, "from-snapshot")
    }

    func testRolloutReconstructionRestoresPreviousTurnSettings() throws {
        func context(
            _ turn: String?, _ model: String, hash: String? = nil, realtime: Bool? = nil
        ) -> RolloutItem {
            .turnContext(TurnContextItem(
                turnId: turn, cwd: "/workspace", model: model,
                compHash: hash, realtimeActive: realtime
            ))
        }
        func userTurn(_ id: String, _ model: String, _ hash: String) -> [RolloutItem] {
            [
                .eventMsg(.turnStarted(TurnStartedEvent(turnId: id))),
                .eventMsg(.userMessage(UserMessageEvent(message: id))),
                context(id, model, hash: hash, realtime: true),
                .eventMsg(.turnComplete(TurnCompleteEvent(turnId: id))),
            ]
        }

        let restored = ContextManager()
        RolloutReconstruction.restoreVerifiedAnswers(
            from: userTurn("keep", "kept-model", "hash-a"),
            into: restored
        )
        XCTAssertEqual(restored.reconstructedTurnSettings?.model, "kept-model")
        XCTAssertEqual(restored.reconstructedTurnSettings?.compHash, "hash-a")
        XCTAssertEqual(restored.reconstructedTurnSettings?.realtimeActive, true)

        let bare = ContextManager()
        RolloutReconstruction.restoreVerifiedAnswers(
            from: [context("solo", "bare-model", hash: "hash-b")],
            into: bare
        )
        XCTAssertNil(bare.reconstructedTurnSettings)

        let rolled = ContextManager()
        RolloutReconstruction.restoreVerifiedAnswers(
            from: userTurn("keep", "kept-model", "hash-a")
                + userTurn("drop", "dropped-model", "hash-b")
                + [.eventMsg(.threadRolledBack(ThreadRolledBackEvent(numTurns: 1)))],
            into: rolled
        )
        XCTAssertEqual(rolled.reconstructedTurnSettings?.model, "kept-model")
        XCTAssertEqual(rolled.reconstructedTurnSettings?.compHash, "hash-a")

        var bounded = CompactedItem(message: "summary")
        bounded.replacementHistory = []
        bounded.windowNumber = 1
        bounded.resumeMetadata = .object([
            "previous_turn_settings": .object([
                "model": .string("metadata-model"),
                "comp_hash": .string("metadata-hash"),
            ]),
        ])
        let fallback = ContextManager()
        RolloutReconstruction.restoreVerifiedAnswers(from: [.compacted(bounded)], into: fallback)
        XCTAssertEqual(fallback.reconstructedTurnSettings?.model, "metadata-model")
        XCTAssertEqual(fallback.reconstructedTurnSettings?.compHash, "metadata-hash")

        let overridden = ContextManager()
        RolloutReconstruction.restoreVerifiedAnswers(
            from: [
                .compacted(bounded),
                .worldState(.full(["environment": .object([:])])),
                context("newer", "newer-model", hash: "newer-hash", realtime: false),
                .eventMsg(.turnComplete(TurnCompleteEvent(turnId: "newer"))),
            ],
            into: overridden
        )
        XCTAssertEqual(overridden.reconstructedTurnSettings?.model, "newer-model")
        XCTAssertEqual(overridden.reconstructedTurnSettings?.compHash, "newer-hash")
        XCTAssertEqual(overridden.reconstructedTurnSettings?.realtimeActive, false)

        let incomplete = ContextManager()
        RolloutReconstruction.restoreVerifiedAnswers(
            from: [
                .compacted(bounded),
                .eventMsg(.userMessage(UserMessageEvent(message: "open"))),
                context(nil, "open-model", hash: "open-hash", realtime: true),
            ],
            into: incomplete
        )
        XCTAssertEqual(incomplete.reconstructedTurnSettings?.model, "metadata-model")

        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("sage-turn-settings-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let recorder = try RolloutRecorder.create(
            config: RolloutConfig(codexHome: home.path),
            params: .new(conversationId: ThreadId(), source: .cli, originator: "sage-test")
        )
        try recorder.recordItems(userTurn("keep", "kept-model", "hash-a"))
        try recorder.flush()
        let sess = Session()
        sess.restoreVerifiedAnswers(fromRolloutPath: recorder.rolloutPath)
        XCTAssertEqual(sess.previousTurnSettingsValue()?.model, "kept-model")
        XCTAssertEqual(sess.previousTurnSettingsValue()?.compHash, "hash-a")
        XCTAssertEqual(sess.previousTurnSettingsValue()?.realtimeActive, true)
    }

    func testRolloutReconstructionRestoresLastStartedTurnId() throws {
        let newest = ContextManager()
        RolloutReconstruction.restoreVerifiedAnswers(
            from: [
                .eventMsg(.turnStarted(TurnStartedEvent(turnId: "older"))),
                .eventMsg(.turnStarted(TurnStartedEvent(turnId: "newer"))),
            ],
            into: newest
        )
        XCTAssertEqual(newest.reconstructedLastStartedTurnId, "newer")

        var bounded = CompactedItem(message: "summary")
        bounded.replacementHistory = []
        bounded.windowNumber = 1
        bounded.resumeMetadata = .object([
            "last_started_turn_id": .string("from-metadata"),
        ])
        let fromMetadata = ContextManager()
        RolloutReconstruction.restoreVerifiedAnswers(
            from: [
                .eventMsg(.turnStarted(TurnStartedEvent(turnId: "before"))),
                .compacted(bounded),
            ],
            into: fromMetadata
        )
        XCTAssertEqual(fromMetadata.reconstructedLastStartedTurnId, "from-metadata")

        let afterCheckpoint = ContextManager()
        RolloutReconstruction.restoreVerifiedAnswers(
            from: [
                .eventMsg(.turnStarted(TurnStartedEvent(turnId: "before"))),
                .compacted(bounded),
                .eventMsg(.turnStarted(TurnStartedEvent(turnId: "after"))),
                .eventMsg(.threadRolledBack(ThreadRolledBackEvent(numTurns: 1))),
            ],
            into: afterCheckpoint
        )
        XCTAssertEqual(afterCheckpoint.reconstructedLastStartedTurnId, "after")

        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("sage-last-turn-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let recorder = try RolloutRecorder.create(
            config: RolloutConfig(codexHome: home.path),
            params: .new(conversationId: ThreadId(), source: .cli, originator: "sage-test")
        )
        try recorder.recordItems([
            .eventMsg(.turnStarted(TurnStartedEvent(turnId: "file-turn"))),
        ])
        try recorder.flush()
        let sess = Session()
        sess.lastStartedTurnId = "stale"
        sess.restoreVerifiedAnswers(fromRolloutPath: recorder.rolloutPath)
        XCTAssertEqual(sess.lastStartedTurnId, "file-turn")
        XCTAssertEqual(sess.state.lastStartedTurnId, "file-turn")
    }

    func testRolloutReconstructionRestoresContextWindowFromSessionMeta() {
        let windowId = contextWindowUUID("000000000001")
        var meta = SessionMeta()
        meta.contextWindow = SessionContextWindow(windowId: windowId.uuidString)
        let history = ContextManager()
        RolloutReconstruction.restoreVerifiedAnswers(
            from: [.sessionMeta(SessionMetaLine(meta: meta))],
            into: history
        )
        XCTAssertEqual(history.reconstructedContextWindow?.number, 0)
        XCTAssertEqual(history.reconstructedContextWindow?.firstWindowId, windowId)
        XCTAssertNil(history.reconstructedContextWindow?.previousWindowId)
        XCTAssertEqual(history.reconstructedContextWindow?.windowId, windowId)

        let ignored = ContextManager()
        meta.contextWindow = SessionContextWindow(
            windowId: "0199e6c0-0000-4000-8000-000000000004")
        RolloutReconstruction.restoreVerifiedAnswers(
            from: [.sessionMeta(SessionMetaLine(meta: meta))],
            into: ignored
        )
        XCTAssertEqual(ignored.reconstructedContextWindow?.number, 0)
        XCTAssertNil(ignored.reconstructedContextWindow?.windowId)
    }

    func testRolloutReconstructionPrefersCompactionWindow() {
        let initial = contextWindowUUID("000000000001")
        let first = contextWindowUUID("000000000002")
        let previous = contextWindowUUID("000000000003")
        let current = contextWindowUUID("000000000004")
        var meta = SessionMeta()
        meta.contextWindow = SessionContextWindow(windowId: initial.uuidString)
        var compacted = CompactedItem(message: "summary")
        compacted.windowNumber = 2
        compacted.firstWindowId = first.uuidString
        compacted.previousWindowId = previous.uuidString
        compacted.windowId = current.uuidString
        let history = ContextManager()
        RolloutReconstruction.restoreVerifiedAnswers(
            from: [
                .sessionMeta(SessionMetaLine(meta: meta)),
                .compacted(compacted),
            ],
            into: history
        )
        XCTAssertEqual(history.reconstructedContextWindow?.number, 2)
        XCTAssertEqual(history.reconstructedContextWindow?.firstWindowId, first)
        XCTAssertEqual(history.reconstructedContextWindow?.previousWindowId, previous)
        XCTAssertEqual(history.reconstructedContextWindow?.windowId, current)

        compacted.firstWindowId = "0199e6c0-0000-4000-8000-000000000004"
        compacted.previousWindowId = "not-a-uuid"
        let partial = ContextManager()
        RolloutReconstruction.restoreVerifiedAnswers(
            from: [.compacted(compacted)],
            into: partial
        )
        XCTAssertEqual(partial.reconstructedContextWindow?.number, 2)
        XCTAssertNil(partial.reconstructedContextWindow?.firstWindowId)
        XCTAssertNil(partial.reconstructedContextWindow?.previousWindowId)
        XCTAssertEqual(partial.reconstructedContextWindow?.windowId, current)
    }

    func testRolloutReconstructionKeepsBoundingCompactionWindow() {
        let kept = contextWindowUUID("00000000000a")
        let dropped = contextWindowUUID("00000000000b")
        var older = CompactedItem(message: "older")
        older.windowNumber = 1
        older.windowId = dropped.uuidString
        var bounded = CompactedItem(message: "summary")
        bounded.replacementHistory = []
        bounded.windowNumber = 4
        bounded.windowId = kept.uuidString
        bounded.resumeMetadata = .object([:])
        let history = ContextManager()
        RolloutReconstruction.restoreVerifiedAnswers(
            from: [
                .compacted(older),
                .eventMsg(.turnStarted(TurnStartedEvent(turnId: "old"))),
                .eventMsg(.userMessage(UserMessageEvent(message: "old"))),
                .eventMsg(.turnStarted(TurnStartedEvent(turnId: "new"))),
                .compacted(bounded),
                .eventMsg(.userMessage(UserMessageEvent(message: "after"))),
                .eventMsg(.threadRolledBack(ThreadRolledBackEvent(numTurns: 1))),
            ],
            into: history
        )
        XCTAssertEqual(history.reconstructedContextWindow?.number, 4)
        XCTAssertEqual(history.reconstructedContextWindow?.windowId, kept)
    }

    func testRolloutReconstructionUsesLegacyCompactionCount() {
        let windowId = contextWindowUUID("000000000001")
        var meta = SessionMeta()
        meta.contextWindow = SessionContextWindow(windowId: windowId.uuidString)
        let history = ContextManager()
        RolloutReconstruction.restoreVerifiedAnswers(
            from: [
                .sessionMeta(SessionMetaLine(meta: meta)),
                .compacted(CompactedItem(message: "legacy")),
                .compacted(CompactedItem(message: "again")),
            ],
            into: history
        )
        XCTAssertEqual(history.reconstructedContextWindow?.number, 2)
        XCTAssertNil(history.reconstructedContextWindow?.firstWindowId)
        XCTAssertNil(history.reconstructedContextWindow?.previousWindowId)
        XCTAssertNil(history.reconstructedContextWindow?.windowId)

        var rolledBack = CompactedItem(message: "newer")
        rolledBack.windowNumber = 9
        rolledBack.windowId = contextWindowUUID("000000000009").uuidString
        var kept = CompactedItem(message: "older")
        kept.windowNumber = 1
        kept.windowId = windowId.uuidString
        let surviving = ContextManager()
        RolloutReconstruction.restoreVerifiedAnswers(
            from: [
                .compacted(kept),
                .eventMsg(.turnStarted(TurnStartedEvent(turnId: "old"))),
                .eventMsg(.userMessage(UserMessageEvent(message: "old"))),
                .eventMsg(.turnStarted(TurnStartedEvent(turnId: "new"))),
                .eventMsg(.userMessage(UserMessageEvent(message: "new"))),
                .compacted(rolledBack),
                .eventMsg(.threadRolledBack(ThreadRolledBackEvent(numTurns: 1))),
            ],
            into: surviving
        )
        XCTAssertEqual(surviving.reconstructedContextWindow?.number, 1)
        XCTAssertEqual(surviving.reconstructedContextWindow?.windowId, windowId)
    }

    func testRolloutReconstructionAppliesContextWindow() throws {
        let first = contextWindowUUID("000000000002")
        let previous = contextWindowUUID("000000000003")
        let current = contextWindowUUID("000000000004")
        var compacted = CompactedItem(message: "summary")
        compacted.replacementHistory = []
        compacted.windowNumber = 2
        compacted.firstWindowId = first.uuidString
        compacted.previousWindowId = previous.uuidString
        compacted.windowId = current.uuidString
        compacted.resumeMetadata = .object([:])
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("sage-window-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let recorder = try RolloutRecorder.create(
            config: RolloutConfig(codexHome: home.path),
            params: .new(conversationId: ThreadId(), source: .cli, originator: "sage-test")
        )
        try recorder.recordItems([.compacted(compacted)])
        try recorder.flush()
        let sess = Session()
        sess.restoreVerifiedAnswers(fromRolloutPath: recorder.rolloutPath)
        XCTAssertEqual(sess.state.autoCompactWindowNumber(), 2)
        XCTAssertEqual(sess.state.autoCompactWindowIds().firstWindowId, first)
        XCTAssertEqual(sess.state.autoCompactWindowIds().previousWindowId, previous)
        XCTAssertEqual(sess.state.autoCompactWindowIds().windowId, current)
    }

    func testRolloutReconstructionAppliesLegacyWindowFallback() throws {
        let legacyHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("sage-legacy-window-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: legacyHome, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: legacyHome) }
        let legacy = try RolloutRecorder.create(
            config: RolloutConfig(codexHome: legacyHome.path),
            params: .new(conversationId: ThreadId(), source: .cli, originator: "sage-test")
        )
        try legacy.recordItems([.compacted(CompactedItem(message: "legacy"))])
        try legacy.flush()
        let legacySession = Session()
        let original = legacySession.state.autoCompactWindowIds()
        legacySession.state.restoreAutoCompactWindow(windowNumber: 7, ids: original)
        legacySession.restoreVerifiedAnswers(fromRolloutPath: legacy.rolloutPath)
        XCTAssertEqual(legacySession.state.autoCompactWindowNumber(), 1)
        XCTAssertEqual(legacySession.state.autoCompactWindowIds().windowId, original.windowId)
        XCTAssertEqual(
            legacySession.state.autoCompactWindowIds().firstWindowId, original.windowId)
        XCTAssertNil(legacySession.state.autoCompactWindowIds().previousWindowId)
    }

    private func contextWindowUUID(_ suffix: String) -> UUID {
        let raw = "0199e6c0-0000-7000-8000-\(suffix)"
        guard let uuid = UUID(uuidString: raw) else {
            XCTFail("expected UUID \(raw)")
            return UUID()
        }
        return uuid
    }

    func testRequestUserInputToolRejectsNonRootThread() async throws {
        let sess = Session()
        let turn = TurnContext(sessionSource: .internal(.guardian))
        turn.collaborationMode = CollaborationMode(
            mode: .plan,
            settings: CodexProtocol.Settings(model: turn.model)
        )
        let step = StepContext(turn: turn)
        _ = assembleToolRouter(sess: sess, stepContext: step)
        let output = try await ToolCallRuntime(session: sess, stepContext: step).handleToolCall(
            ToolCall(
                toolName: ToolName(plain: REQUEST_USER_INPUT_TOOL_NAME),
                callId: "call-child",
                payload: .function(arguments: "{}")
            ),
            cancellationToken: CancellationToken()
        )
        guard case .functionCallOutput(_, let callId, _, _, let payload, _) = output else {
            return XCTFail("expected function call output")
        }
        XCTAssertEqual(callId, "call-child")
        XCTAssertEqual(
            payload.body.toText(),
            "request_user_input can only be used by the root thread"
        )
        XCTAssertFalse(sess.emittedEvents.contains { event in
            if case .requestUserInput = event { return true }
            return false
        })
        XCTAssertNil(sess.activeTurn)
    }

    func testRequestPermissionsToolWaitsForTheResponse() async throws {
        let sess = Session()
        let entered = expectation(description: "sampling")
        let gate = SubmissionAck()
        defer {
            sess.activeTurn?.turnState.clearPendingWaiters()
            gate.signal()
        }
        sess.runSamplingOverride = { _, _ in
            entered.fulfill()
            await gate.wait()
            return SamplingRequestResult(needsFollowUp: false, lastAgentMessage: "kept")
        }
        _ = try await sess.submit(
            .userInput(TurnInputBuilder.user([.text(text: "hello", textElements: [])]))
        )
        await fulfillment(of: [entered], timeout: 1)
        let live = try XCTUnwrap(sess.activeTurn?.task?.turnContext)
        let started = sess.emittedEvents.filter { event in
            if case .turnStarted = event { return true }
            return false
        }.count
        var registry = HarnessToolRegistry()
        registry.register(RequestPermissionsHandler())
        let step = StepContext(
            turn: live,
            toolRouter: ToolRouter(
                registry: registry,
                modelVisibleSpecs: [],
                toolMode: .direct,
                canManageChildren: false
            )
        )
        step.environments = [
            TurnEnvironment(environmentId: "workspace", cwd: "/tmp/sage-workspace"),
        ]
        let arguments = """
        {"environment_id":"workspace","reason":"fetch","permissions":{"network":{"enabled":true}}}
        """
        let outputTask = Task {
            try await ToolCallRuntime(session: sess, stepContext: step).handleToolCall(
                ToolCall(
                    toolName: ToolName(plain: "request_permissions"),
                    callId: "call-perm",
                    payload: .function(arguments: arguments)
                ),
                cancellationToken: CancellationToken()
            )
        }
        try await waitUntil {
            sess.emittedEvents.contains { event in
                if case .requestPermissions(let requested) = event {
                    return requested.callId == "call-perm"
                        && requested.turnId == live.subId
                        && requested.environmentId == "workspace"
                        && requested.reason == "fetch"
                }
                return false
            }
        }
        let requested = RequestPermissionProfile(network: NetworkPermissions(enabled: true))
        _ = try await sess.submit(
            .requestPermissionsResponse(
                id: "call-perm",
                response: RequestPermissionsResponse(
                    permissions: requested, scope: .turn, strictAutoReview: true)
            )
        )
        let output = try await outputTask.value
        guard case .functionCallOutput(_, let callId, _, _, let payload, _) = output else {
            return XCTFail("expected function call output")
        }
        XCTAssertEqual(callId, "call-perm")
        XCTAssertEqual(payload.body.toText()?.contains("\"scope\":\"turn\""), true)
        XCTAssertEqual(
            sess.activeTurn?.turnState.grantedPermissions(environmentId: "workspace")?.network?.enabled,
            true
        )
        XCTAssertEqual(sess.activeTurn?.turnState.strictAutoReviewEnabled, true)
        XCTAssertEqual(
            sess.emittedEvents.filter { event in
                if case .turnStarted = event { return true }
                return false
            }.count,
            started
        )
        gate.signal()
        await sess.waitUntilIdle()
        XCTAssertEqual(sess.lastTaskAgentMessage, "kept")
        XCTAssertEqual(sess.lastStartedTurnId, live.subId)
    }

    func testRequestPermissionsToolWithoutATurnReturnsCancelled() async throws {
        let sess = Session()
        var registry = HarnessToolRegistry()
        registry.register(RequestPermissionsHandler())
        let step = StepContext(
            toolRouter: ToolRouter(
                registry: registry,
                modelVisibleSpecs: [],
                toolMode: .direct,
                canManageChildren: false
            )
        )
        let output = try await ToolCallRuntime(session: sess, stepContext: step).handleToolCall(
            ToolCall(
                toolName: ToolName(plain: "request_permissions"),
                callId: "call-idle",
                payload: .function(arguments: #"{"permissions":{"network":{"enabled":true}}}"#)
            ),
            cancellationToken: CancellationToken()
        )
        guard case .functionCallOutput(_, let callId, _, _, let payload, _) = output else {
            return XCTFail("expected function call output")
        }
        XCTAssertEqual(callId, "call-idle")
        XCTAssertEqual(
            payload.body.toText(),
            "request_permissions was cancelled before receiving a response"
        )
        XCTAssertTrue(sess.emittedEvents.contains { event in
            if case .requestPermissions(let requested) = event {
                return requested.callId == "call-idle"
            }
            return false
        })
        XCTAssertNil(sess.activeTurn)
        XCTAssertNil(sess.lastStartedTurnId)
    }

    func testRequestPermissionsToolResolvesPathsAgainstTheTurnEnvironment() async throws {
        let sess = Session()
        var registry = HarnessToolRegistry()
        registry.register(RequestPermissionsHandler())
        let step = StepContext(
            toolRouter: ToolRouter(
                registry: registry,
                modelVisibleSpecs: [],
                toolMode: .direct,
                canManageChildren: false
            )
        )
        step.environments = [
            TurnEnvironment(
                environmentId: "workspace",
                cwd: "/tmp/sage-perms",
                userHomeDir: "/Users/sage"
            ),
        ]
        let arguments = """
        {"environment_id":"workspace","permissions":{"file_system":{"read":["notes","~/docs"],"entries":[{"path":{"type":"path","path":"src"},"access":"write"}]}}}
        """
        let output = try await ToolCallRuntime(session: sess, stepContext: step).handleToolCall(
            ToolCall(
                toolName: ToolName(plain: "request_permissions"),
                callId: "call-paths",
                payload: .function(arguments: arguments)
            ),
            cancellationToken: CancellationToken()
        )
        guard case .functionCallOutput(_, _, _, _, let payload, _) = output else {
            return XCTFail("expected function call output")
        }
        XCTAssertEqual(
            payload.body.toText(),
            "request_permissions was cancelled before receiving a response"
        )
        let requested = try XCTUnwrap(sess.emittedEvents.compactMap { event -> RequestPermissionsEvent? in
            if case .requestPermissions(let requested) = event, requested.callId == "call-paths" {
                return requested
            }
            return nil
        }.first)
        XCTAssertEqual(
            requested.permissions.fileSystem?.entries.map(permissionPathText),
            [
                "write /tmp/sage-perms/src",
                "read /tmp/sage-perms/notes",
                "read /Users/sage/docs",
            ]
        )

        let unknown = try await ToolCallRuntime(session: sess, stepContext: step).handleToolCall(
            ToolCall(
                toolName: ToolName(plain: "request_permissions"),
                callId: "call-missing",
                payload: .function(arguments: #"{"environment_id":"missing","permissions":{"network":{"enabled":true}}}"#)
            ),
            cancellationToken: CancellationToken()
        )
        guard case .functionCallOutput(_, _, _, _, let unknownPayload, _) = unknown else {
            return XCTFail("expected function call output")
        }
        XCTAssertEqual(unknownPayload.body.toText(), "unknown turn environment id `missing`")
        XCTAssertFalse(sess.emittedEvents.contains { event in
            if case .requestPermissions(let requested) = event {
                return requested.callId == "call-missing"
            }
            return false
        })
    }

    func testRequestPermissionsRequiresAPrimaryEnvironment() async throws {
        var invocation = ToolInvocation(
            callId: "call-none",
            toolName: ToolName(plain: "request_permissions"),
            payload: .function(arguments: #"{"permissions":{"network":{"enabled":true}}}"#)
        )
        let called = PermissionCallbackFlag()
        invocation.onRequestPermissions = { _, _ in
            called.value = true
            return nil
        }
        do {
            _ = try await RequestPermissionsHandler().handle(invocation)
            XCTFail("expected a missing environment")
        } catch let error as FunctionCallError {
            guard case .respondToModel(let message) = error else {
                return XCTFail("expected a model response")
            }
            XCTAssertEqual(message, "request_permissions requires a primary environment")
        }
        XCTAssertFalse(called.value)
    }

    func testRequestPermissionsGuardianAllowSkipsTheUserCard() async throws {
        let sess = Session()
        let entered = expectation(description: "sampling")
        let gate = SubmissionAck()
        defer {
            sess.activeTurn?.turnState.clearPendingWaiters()
            gate.signal()
        }
        sess.runSamplingOverride = { _, _ in
            entered.fulfill()
            await gate.wait()
            return SamplingRequestResult(needsFollowUp: false, lastAgentMessage: "kept")
        }
        sess.requestPermissionsGuardian = { _ in .approved }
        _ = try await sess.submit(
            .userInput(TurnInputBuilder.user([.text(text: "hello", textElements: [])]))
        )
        await fulfillment(of: [entered], timeout: 1)
        let live = try XCTUnwrap(sess.activeTurn?.task?.turnContext)
        let started = sess.emittedEvents.filter { event in
            if case .turnStarted = event { return true }
            return false
        }.count
        var registry = HarnessToolRegistry()
        registry.register(RequestPermissionsHandler())
        let step = StepContext(
            turn: live,
            toolRouter: ToolRouter(
                registry: registry,
                modelVisibleSpecs: [],
                toolMode: .direct,
                canManageChildren: false
            )
        )
        step.environments = [
            TurnEnvironment(environmentId: "workspace", cwd: "/tmp/sage-workspace"),
        ]
        let output = try await ToolCallRuntime(session: sess, stepContext: step).handleToolCall(
            ToolCall(
                toolName: ToolName(plain: "request_permissions"),
                callId: "call-guard",
                payload: .function(
                    arguments: #"{"environment_id":"workspace","permissions":{"network":{"enabled":true}}}"#
                )
            ),
            cancellationToken: CancellationToken()
        )
        guard case .functionCallOutput(_, let callId, _, _, let payload, _) = output else {
            return XCTFail("expected function call output")
        }
        XCTAssertEqual(callId, "call-guard")
        let text = payload.body.toText()
        let response = try JSONDecoder().decode(
            RequestPermissionsResponse.self, from: Data((text ?? "").utf8))
        XCTAssertEqual(response.permissions.network?.enabled, true)
        XCTAssertEqual(response.scope, .turn)
        XCTAssertFalse(response.strictAutoReview)
        XCTAssertEqual(text?.contains("strict_auto_review"), false)
        XCTAssertEqual(requestPermissionEventCount(sess, callId: "call-guard"), 0)
        XCTAssertEqual(
            sess.activeTurn?.turnState.grantedPermissions(environmentId: "workspace")?.network?.enabled,
            true
        )
        XCTAssertNil(sess.state.grantedPermissions(environmentId: "workspace"))
        XCTAssertEqual(sess.activeTurn?.turnState.strictAutoReviewEnabled, false)
        XCTAssertEqual(
            sess.emittedEvents.filter { event in
                if case .turnStarted = event { return true }
                return false
            }.count,
            started
        )
        gate.signal()
        await sess.waitUntilIdle()
        XCTAssertEqual(sess.lastTaskAgentMessage, "kept")
    }

    func testRequestPermissionsGuardianDecisionsAndPolicyShortCircuit() async throws {
        let sess = Session()
        sess.state.sessionConfiguration.originalConfig.approvalPolicy = .never
        let entered = expectation(description: "sampling")
        let gate = SubmissionAck()
        defer {
            sess.activeTurn?.turnState.clearPendingWaiters()
            gate.signal()
        }
        sess.runSamplingOverride = { _, _ in
            entered.fulfill()
            await gate.wait()
            return SamplingRequestResult(needsFollowUp: false, lastAgentMessage: "kept")
        }
        let called = PermissionCallbackFlag()
        sess.requestPermissionsGuardian = { _ in
            called.value = true
            return .approved
        }
        _ = try await sess.submit(
            .userInput(TurnInputBuilder.user([.text(text: "hello", textElements: [])]))
        )
        await fulfillment(of: [entered], timeout: 1)
        let turn = try XCTUnwrap(sess.activeTurn?.task?.turnContext)
        XCTAssertEqual(turn.approvalPolicy, .never)
        let requested = RequestPermissionProfile(network: NetworkPermissions(enabled: true))
        let args = RequestPermissionsArgs(
            environmentId: "workspace", reason: "fetch", permissions: requested)
        let blocked = await sess.requestPermissions(
            turnContext: turn, callId: "call-never", args: args,
            cancellationToken: CancellationToken())
        XCTAssertEqual(blocked?.permissions.isEmpty, true)
        XCTAssertEqual(blocked?.scope, .turn)
        XCTAssertEqual(blocked?.strictAutoReview, false)
        XCTAssertFalse(called.value)
        XCTAssertEqual(requestPermissionEventCount(sess), 0)

        turn.approvalPolicy = .granular(
            GranularApprovalConfig(
                sandboxApproval: true, rules: true, requestPermissions: false, mcpElicitations: false)
        )
        let granular = await sess.requestPermissions(
            turnContext: turn, callId: "call-granular", args: args,
            cancellationToken: CancellationToken())
        XCTAssertEqual(granular?.permissions.isEmpty, true)
        XCTAssertFalse(called.value)
        XCTAssertEqual(requestPermissionEventCount(sess), 0)

        turn.approvalPolicy = .onRequest
        sess.requestPermissionsGuardian = { _ in .denied(rejection: "no") }
        let denied = await sess.requestPermissions(
            turnContext: turn, callId: "call-deny", args: args,
            cancellationToken: CancellationToken())
        XCTAssertEqual(denied?.permissions.isEmpty, true)
        XCTAssertEqual(denied?.scope, .turn)
        XCTAssertNil(sess.activeTurn?.turnState.grantedPermissions(environmentId: "workspace"))
        XCTAssertEqual(requestPermissionEventCount(sess), 0)

        sess.requestPermissionsGuardian = { _ in .approvedForSession }
        let sessionGrant = await sess.requestPermissions(
            turnContext: turn, callId: "call-session", args: args,
            cancellationToken: CancellationToken())
        XCTAssertEqual(sessionGrant?.scope, .session)
        XCTAssertEqual(sessionGrant?.permissions.network?.enabled, true)
        XCTAssertEqual(sessionGrant?.strictAutoReview, false)
        XCTAssertEqual(
            sess.state.grantedPermissions(environmentId: "workspace")?.network?.enabled, true)
        XCTAssertNil(sess.activeTurn?.turnState.grantedPermissions(environmentId: "workspace"))
        XCTAssertEqual(requestPermissionEventCount(sess), 0)

        sess.requestPermissionsGuardian = { _ in
            .approvedExecpolicyAmendment(proposedExecpolicyAmendment: ExecPolicyAmendment(["ls"]))
        }
        let amended = await sess.requestPermissions(
            turnContext: turn, callId: "call-amend", args: args,
            cancellationToken: CancellationToken())
        XCTAssertEqual(amended?.scope, .turn)
        XCTAssertEqual(amended?.permissions.network?.enabled, true)
        XCTAssertEqual(
            sess.activeTurn?.turnState.grantedPermissions(environmentId: "workspace")?.network?.enabled,
            true
        )

        sess.requestPermissionsGuardian = { _ in
            .networkPolicyAmendment(
                networkPolicyAmendment: NetworkPolicyAmendment(host: "example.com", action: .deny))
        }
        let networkDeny = await sess.requestPermissions(
            turnContext: turn, callId: "call-net", args: args,
            cancellationToken: CancellationToken())
        XCTAssertEqual(networkDeny?.permissions.isEmpty, true)
        XCTAssertEqual(requestPermissionEventCount(sess), 0)

        sess.requestPermissionsGuardian = { _ in .abort }
        let aborted = await sess.requestPermissions(
            turnContext: turn, callId: "call-abort", args: args,
            cancellationToken: CancellationToken())
        XCTAssertEqual(aborted?.permissions.isEmpty, true)

        let token = CancellationToken()
        token.cancel()
        called.value = false
        sess.requestPermissionsGuardian = { _ in
            called.value = true
            return .approved
        }
        let cancelled = await sess.requestPermissions(
            turnContext: turn, callId: "call-cancel", args: args, cancellationToken: token)
        XCTAssertNil(cancelled)
        XCTAssertFalse(called.value)
        XCTAssertEqual(requestPermissionEventCount(sess), 0)

        sess.requestPermissionsGuardian = { _ in nil }
        let waiting = Task {
            await sess.requestPermissions(
                turnContext: turn, callId: "call-ask", args: args,
                cancellationToken: CancellationToken())
        }
        try await waitUntil {
            requestPermissionEventCount(sess, callId: "call-ask") == 1
        }
        sess.activeTurn?.turnState.clearPendingWaiters()
        let asked = await waiting.value
        XCTAssertNil(asked)

        gate.signal()
        await sess.waitUntilIdle()
    }

    func testRequestPermissionsPolicyContextUsesWorkspaceRootsAndTemporaryDirectories() async throws {
        let context = try permissionPolicyContext(
            TurnEnvironment(
                cwd: "/tmp/sage-perms",
                userHomeDir: "/Users/sage",
                workspaceRoots: ["/tmp/sage-root-a", "/tmp/sage-root-b"],
                temporaryDirectories: ["/tmp/sage-tmp-a", "/tmp/sage-tmp-b"]
            )
        )
        XCTAssertEqual(
            context.workspaceRoots.map { $0.inferredNativePathString() },
            ["/tmp/sage-root-a", "/tmp/sage-root-b"]
        )
        XCTAssertEqual(
            context.temporaryDirectories?.map { $0.inferredNativePathString() },
            ["/tmp/sage-tmp-a", "/tmp/sage-tmp-b"]
        )
        let bare = try permissionPolicyContext(
            TurnEnvironment(
                cwd: "/tmp/sage-perms",
                userHomeDir: nil,
                workspaceRoots: [],
                temporaryDirectories: nil
            )
        )
        XCTAssertEqual(bare.workspaceRoots.map { $0.inferredNativePathString() }, ["/tmp/sage-perms"])
        XCTAssertNil(bare.temporaryDirectories)

        let sess = Session()
        sess.requestPermissionsGuardian = { _ in .approved }
        let expanded = try await requestPermissionsToolResponse(
            session: sess,
            environment: TurnEnvironment(
                environmentId: "workspace",
                cwd: "/tmp/sage-perms",
                workspaceRoots: ["/tmp/sage-root-a", "/tmp/sage-root-b"],
                temporaryDirectories: ["/tmp/sage-tmp-a", "/tmp/sage-tmp-b"]
            ),
            callId: "call-roots",
            arguments: projectRootsAndTmpdirArguments
        )
        XCTAssertEqual(
            expanded.permissions.fileSystem?.entries.map(permissionPathText).sorted(),
            [
                "read /tmp/sage-tmp-a",
                "read /tmp/sage-tmp-b",
                "write /tmp/sage-root-a/src",
                "write /tmp/sage-root-b/src",
            ]
        )
        XCTAssertEqual(requestPermissionEventCount(sess), 0)

        let emptyTemps = try await requestPermissionsToolResponse(
            session: sess,
            environment: TurnEnvironment(
                environmentId: "workspace",
                cwd: "/tmp/sage-perms",
                workspaceRoots: ["/tmp/sage-root-a"],
                temporaryDirectories: []
            ),
            callId: "call-empty-tmp",
            arguments: #"{"environment_id":"workspace","permissions":{"file_system":{"entries":[{"path":{"type":"special","value":{"kind":"tmpdir"}},"access":"read"}]}}}"#
        )
        XCTAssertNil(emptyTemps.permissions.fileSystem)
        let processTemp = ProcessInfo.processInfo.environment["TMPDIR"] ?? ""
        if !processTemp.isEmpty {
            let rendered = emptyTemps.permissions.fileSystem?.entries.map(permissionPathText) ?? []
            XCTAssertFalse(rendered.contains { $0.contains(processTemp) })
        }

        let unsetTemps = try await requestPermissionsToolResponse(
            session: sess,
            environment: TurnEnvironment(
                environmentId: "workspace",
                cwd: "/tmp/sage-perms",
                workspaceRoots: ["/tmp/sage-root-a"],
                temporaryDirectories: nil
            ),
            callId: "call-unset-tmp",
            arguments: #"{"environment_id":"workspace","permissions":{"file_system":{"entries":[{"path":{"type":"special","value":{"kind":"tmpdir"}},"access":"read"}]}}}"#
        )
        XCTAssertEqual(
            unsetTemps.permissions.fileSystem?.entries.map(\.path),
            [.special(value: .tmpdir)]
        )
    }

    func testRequestPermissionsUserGrantIntersectsWorkspaceRoots() async throws {
        let sess = Session()
        let entered = expectation(description: "sampling")
        let gate = SubmissionAck()
        defer {
            sess.activeTurn?.turnState.clearPendingWaiters()
            gate.signal()
        }
        sess.runSamplingOverride = { _, _ in
            entered.fulfill()
            await gate.wait()
            return SamplingRequestResult(needsFollowUp: false, lastAgentMessage: "kept")
        }
        _ = try await sess.submit(
            .userInput(TurnInputBuilder.user([.text(text: "hello", textElements: [])]))
        )
        await fulfillment(of: [entered], timeout: 1)
        let live = try XCTUnwrap(sess.activeTurn?.task?.turnContext)
        var registry = HarnessToolRegistry()
        registry.register(RequestPermissionsHandler())
        let step = StepContext(
            turn: live,
            toolRouter: ToolRouter(
                registry: registry,
                modelVisibleSpecs: [],
                toolMode: .direct,
                canManageChildren: false
            )
        )
        step.environments = [
            TurnEnvironment(
                environmentId: "workspace",
                cwd: "/tmp/sage-perms",
                workspaceRoots: ["/tmp/sage-root-a", "/tmp/sage-root-b"],
                temporaryDirectories: ["/tmp/sage-tmp-a", "/tmp/sage-tmp-b"]
            ),
        ]
        let outputTask = Task {
            try await ToolCallRuntime(session: sess, stepContext: step).handleToolCall(
                ToolCall(
                    toolName: ToolName(plain: "request_permissions"),
                    callId: "call-grant",
                    payload: .function(arguments: projectRootsAndTmpdirArguments)
                ),
                cancellationToken: CancellationToken()
            )
        }
        try await waitUntil {
            requestPermissionEventCount(sess, callId: "call-grant") == 1
        }
        let requested = try XCTUnwrap(sess.emittedEvents.compactMap { event -> RequestPermissionsEvent? in
            if case .requestPermissions(let requested) = event, requested.callId == "call-grant" {
                return requested
            }
            return nil
        }.first)
        XCTAssertEqual(
            requested.permissions.fileSystem?.entries.map(\.path),
            [
                .special(value: .projectRoots(subpath: "src")),
                .special(value: .tmpdir),
            ]
        )
        _ = try await sess.submit(
            .requestPermissionsResponse(
                id: "call-grant",
                response: RequestPermissionsResponse(
                    permissions: requested.permissions, scope: .turn)
            )
        )
        let output = try await outputTask.value
        guard case .functionCallOutput(_, _, _, _, let payload, _) = output else {
            return XCTFail("expected function call output")
        }
        let response = try JSONDecoder().decode(
            RequestPermissionsResponse.self, from: Data((payload.body.toText() ?? "").utf8))
        let expected = [
            "read /tmp/sage-tmp-a",
            "read /tmp/sage-tmp-b",
            "write /tmp/sage-root-a/src",
            "write /tmp/sage-root-b/src",
        ]
        XCTAssertEqual(response.permissions.fileSystem?.entries.map(permissionPathText).sorted(), expected)
        XCTAssertEqual(
            sess.activeTurn?.turnState.grantedPermissions(environmentId: "workspace")?
                .fileSystem?.entries.map(permissionPathText).sorted(),
            expected
        )
        gate.signal()
        await sess.waitUntilIdle()
    }

    func testRequestPermissionsResponseResumesTheWaitingCall() async throws {
        let sess = Session()
        let entered = expectation(description: "sampling")
        let gate = SubmissionAck()
        defer {
            sess.activeTurn?.turnState.clearPendingWaiters()
            gate.signal()
        }
        sess.runSamplingOverride = { _, _ in
            entered.fulfill()
            await gate.wait()
            return SamplingRequestResult(needsFollowUp: false, lastAgentMessage: "kept")
        }
        _ = try await sess.submit(
            .userInput(TurnInputBuilder.user([.text(text: "hello", textElements: [])]))
        )
        await fulfillment(of: [entered], timeout: 1)
        let turn = try XCTUnwrap(sess.activeTurn?.task?.turnContext)
        let started = sess.emittedEvents.filter { event in
            if case .turnStarted = event { return true }
            return false
        }.count
        let requested = RequestPermissionProfile(network: NetworkPermissions(enabled: true))
        let args = RequestPermissionsArgs(
            environmentId: "workspace", reason: "fetch", permissions: requested)
        let grant = RequestPermissionsResponse(
            permissions: requested, scope: .turn, strictAutoReview: true)
        let token = CancellationToken()

        let first = Task {
            await sess.requestPermissions(
                turnContext: turn, callId: "call-1", args: args, cancellationToken: token)
        }
        try await waitUntil {
            sess.emittedEvents.contains { event in
                if case .requestPermissions(let requested) = event {
                    return requested.callId == "call-1"
                        && requested.turnId == turn.subId
                        && requested.environmentId == "workspace"
                }
                return false
            }
        }
        let second = Task {
            await sess.requestPermissions(
                turnContext: turn, callId: "call-1", args: args, cancellationToken: token)
        }
        try await waitUntil {
            sess.emittedEvents.filter { event in
                if case .requestPermissions(let requested) = event {
                    return requested.callId == "call-1"
                }
                return false
            }.count >= 2
        }
        let replaced = await first.value
        XCTAssertNil(replaced)

        _ = try await sess.submit(.requestPermissionsResponse(id: "missing", response: grant))
        XCTAssertEqual(sess.activeTurn?.task?.turnContext.subId, turn.subId)
        XCTAssertNil(sess.activeTurn?.turnState.grantedPermissions(environmentId: "workspace"))
        _ = try await sess.submit(.requestPermissionsResponse(id: "call-1", response: grant))
        let accepted = await second.value
        XCTAssertEqual(accepted, grant)
        XCTAssertEqual(
            sess.activeTurn?.turnState.grantedPermissions(environmentId: "workspace")?.network?.enabled,
            true
        )
        XCTAssertEqual(sess.activeTurn?.turnState.strictAutoReviewEnabled, true)
        XCTAssertNil(sess.state.grantedPermissions(environmentId: "workspace"))
        XCTAssertEqual(
            sess.emittedEvents.filter { event in
                if case .turnStarted = event { return true }
                return false
            }.count,
            started
        )

        let excess = Task {
            await sess.requestPermissions(
                turnContext: turn,
                callId: "call-excess",
                args: RequestPermissionsArgs(environmentId: "workspace", permissions: RequestPermissionProfile()),
                cancellationToken: token
            )
        }
        try await waitUntil {
            sess.emittedEvents.contains { event in
                if case .requestPermissions(let requested) = event {
                    return requested.callId == "call-excess"
                }
                return false
            }
        }
        _ = try await sess.submit(
            .requestPermissionsResponse(
                id: "call-excess",
                response: RequestPermissionsResponse(permissions: requested, scope: .turn)
            )
        )
        let clipped = await excess.value
        XCTAssertEqual(clipped?.permissions, RequestPermissionProfile())
        XCTAssertEqual(clipped?.scope, .turn)
        XCTAssertEqual(
            sess.activeTurn?.turnState.grantedPermissions(environmentId: "workspace")?.network?.enabled,
            true
        )

        gate.signal()
        await sess.waitUntilIdle()
        XCTAssertEqual(sess.lastTaskAgentMessage, "kept")
        XCTAssertEqual(sess.lastStartedTurnId, turn.subId)
    }

    func testRequestPermissionsSessionScopeRecordsOnTheSession() async throws {
        let sess = Session()
        let entered = expectation(description: "sampling")
        let gate = SubmissionAck()
        defer {
            sess.activeTurn?.turnState.clearPendingWaiters()
            gate.signal()
        }
        sess.runSamplingOverride = { _, _ in
            entered.fulfill()
            await gate.wait()
            return SamplingRequestResult(needsFollowUp: false, lastAgentMessage: "kept")
        }
        _ = try await sess.submit(
            .userInput(TurnInputBuilder.user([.text(text: "hello", textElements: [])]))
        )
        await fulfillment(of: [entered], timeout: 1)
        let turn = try XCTUnwrap(sess.activeTurn?.task?.turnContext)
        let requested = RequestPermissionProfile(network: NetworkPermissions(enabled: true))
        let args = RequestPermissionsArgs(environmentId: "workspace", permissions: requested)
        let waiting = Task {
            await sess.requestPermissions(
                turnContext: turn,
                callId: "call-session",
                args: args,
                cancellationToken: CancellationToken()
            )
        }
        try await waitUntil {
            sess.emittedEvents.contains { event in
                if case .requestPermissions(let requested) = event {
                    return requested.callId == "call-session"
                }
                return false
            }
        }
        let grant = RequestPermissionsResponse(permissions: requested, scope: .session)
        _ = try await sess.submit(.requestPermissionsResponse(id: "call-session", response: grant))
        let accepted = await waiting.value
        XCTAssertEqual(accepted, grant)
        XCTAssertEqual(
            sess.state.grantedPermissions(environmentId: "workspace")?.network?.enabled,
            true
        )
        XCTAssertNil(sess.activeTurn?.turnState.grantedPermissions(environmentId: "workspace"))
        XCTAssertEqual(sess.activeTurn?.turnState.strictAutoReviewEnabled, false)
        XCTAssertEqual(sess.activeTurn?.task?.turnContext.subId, turn.subId)
        gate.signal()
        await sess.waitUntilIdle()
    }

    func testRequestPermissionsStrictSessionGrantCollapses() async throws {
        let sess = Session()
        let entered = expectation(description: "sampling")
        let gate = SubmissionAck()
        defer {
            sess.activeTurn?.turnState.clearPendingWaiters()
            gate.signal()
        }
        sess.runSamplingOverride = { _, _ in
            entered.fulfill()
            await gate.wait()
            return SamplingRequestResult(needsFollowUp: false, lastAgentMessage: "kept")
        }
        _ = try await sess.submit(
            .userInput(TurnInputBuilder.user([.text(text: "hello", textElements: [])]))
        )
        await fulfillment(of: [entered], timeout: 1)
        let turn = try XCTUnwrap(sess.activeTurn?.task?.turnContext)
        let requested = RequestPermissionProfile(network: NetworkPermissions(enabled: true))
        let waiting = Task {
            await sess.requestPermissions(
                turnContext: turn,
                callId: "call-strict",
                args: RequestPermissionsArgs(environmentId: "workspace", permissions: requested),
                cancellationToken: CancellationToken()
            )
        }
        try await waitUntil {
            sess.emittedEvents.contains { event in
                if case .requestPermissions(let requested) = event {
                    return requested.callId == "call-strict"
                }
                return false
            }
        }
        _ = try await sess.submit(
            .requestPermissionsResponse(
                id: "call-strict",
                response: RequestPermissionsResponse(
                    permissions: requested, scope: .session, strictAutoReview: true)
            )
        )
        let accepted = await waiting.value
        XCTAssertEqual(accepted?.permissions, RequestPermissionProfile())
        XCTAssertEqual(accepted?.scope, .turn)
        XCTAssertEqual(accepted?.strictAutoReview, false)
        XCTAssertNil(sess.activeTurn?.turnState.grantedPermissions(environmentId: "workspace"))
        XCTAssertNil(sess.state.grantedPermissions(environmentId: "workspace"))
        XCTAssertEqual(sess.activeTurn?.turnState.strictAutoReviewEnabled, false)
        gate.signal()
        await sess.waitUntilIdle()
    }

    func testRequestPermissionsCancellationDropsTheWaiter() async throws {
        let sess = Session()
        let entered = expectation(description: "sampling")
        let gate = SubmissionAck()
        defer {
            sess.activeTurn?.turnState.clearPendingWaiters()
            gate.signal()
        }
        sess.runSamplingOverride = { _, _ in
            entered.fulfill()
            await gate.wait()
            return SamplingRequestResult(needsFollowUp: false, lastAgentMessage: "kept")
        }
        _ = try await sess.submit(
            .userInput(TurnInputBuilder.user([.text(text: "hello", textElements: [])]))
        )
        await fulfillment(of: [entered], timeout: 1)
        let turn = try XCTUnwrap(sess.activeTurn?.task?.turnContext)
        let token = CancellationToken()
        let requested = RequestPermissionProfile(network: NetworkPermissions(enabled: true))
        let waiting = Task {
            await sess.requestPermissions(
                turnContext: turn,
                callId: "call-cancel",
                args: RequestPermissionsArgs(environmentId: "workspace", permissions: requested),
                cancellationToken: token
            )
        }
        try await waitUntil {
            sess.emittedEvents.contains { event in
                if case .requestPermissions(let requested) = event {
                    return requested.callId == "call-cancel"
                }
                return false
            }
        }
        token.cancel()
        let cancelled = await waiting.value
        XCTAssertNil(cancelled)
        _ = try await sess.submit(
            .requestPermissionsResponse(
                id: "call-cancel",
                response: RequestPermissionsResponse(permissions: requested, scope: .turn, strictAutoReview: true)
            )
        )
        XCTAssertNil(sess.activeTurn?.turnState.grantedPermissions(environmentId: "workspace"))
        XCTAssertEqual(sess.activeTurn?.turnState.strictAutoReviewEnabled, false)
        XCTAssertEqual(sess.activeTurn?.task?.turnContext.subId, turn.subId)
        gate.signal()
        await sess.waitUntilIdle()
        XCTAssertEqual(sess.lastTaskAgentMessage, "kept")
    }

    func testRequestPermissionsResponseDoesNothingWhenNobodyIsWaiting() async throws {
        let sess = Session()
        _ = try await sess.submit(
            .requestPermissionsResponse(
                id: "missing",
                response: RequestPermissionsResponse(
                    permissions: RequestPermissionProfile(network: NetworkPermissions(enabled: true))
                )
            )
        )
        XCTAssertNil(sess.activeTurn)
        XCTAssertNil(sess.lastStartedTurnId)
        XCTAssertNil(sess.state.grantedPermissions(environmentId: "local"))
        XCTAssertFalse(sess.emittedEvents.contains { event in
            if case .turnStarted = event { return true }
            return false
        })
    }

    func testDynamicToolResponseResumesTheWaitingCall() async throws {
        let sess = Session()
        let entered = expectation(description: "sampling")
        let gate = SubmissionAck()
        defer {
            sess.activeTurn?.turnState.clearPendingWaiters()
            gate.signal()
        }
        sess.runSamplingOverride = { _, _ in
            entered.fulfill()
            await gate.wait()
            return SamplingRequestResult(needsFollowUp: false, lastAgentMessage: "kept")
        }
        _ = try await sess.submit(
            .userInput(TurnInputBuilder.user([.text(text: "hello", textElements: [])]))
        )
        await fulfillment(of: [entered], timeout: 1)
        let turn = try XCTUnwrap(sess.activeTurn?.task?.turnContext)
        let startedTurns = sess.emittedEvents.filter { event in
            if case .turnStarted = event { return true }
            return false
        }.count
        let arguments = CodexProtocol.JSONValue.object(["q": .string("sage")])
        let found = DynamicToolResponse(
            contentItems: [.inputText(text: "found")], success: true)
        let missing = DynamicToolResponse(
            contentItems: [.inputText(text: "missing")], success: false)

        let succeeded = Task {
            await sess.requestDynamicTool(
                turnContext: turn, callId: "call-ok", namespace: "docs", tool: "lookup",
                arguments: arguments)
        }
        try await waitUntil {
            dynamicToolCalls(in: sess, callId: "call-ok", status: .inProgress).count == 1
        }
        _ = try await sess.submit(.dynamicToolResponse(id: "missing", response: found))
        XCTAssertEqual(sess.activeTurn?.task?.turnContext.subId, turn.subId)
        XCTAssertTrue(dynamicToolCalls(in: sess, callId: "call-ok", status: .completed).isEmpty)
        _ = try await sess.submit(.dynamicToolResponse(id: "call-ok", response: found))
        let accepted = await succeeded.value
        XCTAssertEqual(accepted, found)
        let completed = try XCTUnwrap(
            dynamicToolCalls(in: sess, callId: "call-ok", status: .completed).first)
        XCTAssertEqual(completed.namespace, "docs")
        XCTAssertEqual(completed.tool, "lookup")
        XCTAssertEqual(completed.arguments, arguments)
        XCTAssertEqual(completed.contentItems, [.inputText(text: "found")])
        XCTAssertEqual(completed.success, true)
        XCTAssertNil(completed.error)

        let first = Task {
            await sess.requestDynamicTool(
                turnContext: turn, callId: "call-1", namespace: nil, tool: "lookup",
                arguments: arguments)
        }
        try await waitUntil {
            dynamicToolCalls(in: sess, callId: "call-1", status: .inProgress).count == 1
        }
        let second = Task {
            await sess.requestDynamicTool(
                turnContext: turn, callId: "call-1", namespace: nil, tool: "lookup",
                arguments: arguments)
        }
        try await waitUntil {
            dynamicToolCalls(in: sess, callId: "call-1", status: .inProgress).count == 2
        }
        XCTAssertTrue(dynamicToolCalls(in: sess, callId: "call-1", status: .failed).isEmpty)
        _ = try await sess.submit(.dynamicToolResponse(id: "call-1", response: missing))
        let replacement = await second.value
        let replaced = await first.value
        XCTAssertEqual(replacement, missing)
        XCTAssertNil(replaced)
        XCTAssertEqual(
            dynamicToolCalls(in: sess, callId: "call-1", status: .failed).map(\.error),
            [nil, "dynamic tool call was cancelled before receiving a response"]
        )
        XCTAssertEqual(
            sess.emittedEvents.filter { event in
                if case .turnStarted = event { return true }
                return false
            }.count,
            startedTurns
        )
        gate.signal()
        await sess.waitUntilIdle()
        XCTAssertEqual(sess.lastTaskAgentMessage, "kept")
        XCTAssertEqual(sess.lastStartedTurnId, turn.subId)
    }

    func testDynamicToolRequestWithoutATurnReturnsNil() async {
        let sess = Session()
        let turn = TurnContext(subId: "turn-idle")
        let response = await sess.requestDynamicTool(
            turnContext: turn,
            callId: "call-idle",
            namespace: nil,
            tool: "lookup",
            arguments: CodexProtocol.JSONValue.object([:])
        )
        XCTAssertNil(response)
        XCTAssertNil(sess.activeTurn)
        XCTAssertEqual(
            dynamicToolCalls(in: sess, callId: "call-idle", status: .inProgress).count, 1)
        let failed = dynamicToolCalls(in: sess, callId: "call-idle", status: .failed)
        XCTAssertEqual(failed.count, 1)
        XCTAssertEqual(failed.first?.success, false)
        XCTAssertEqual(
            failed.first?.error,
            "dynamic tool call was cancelled before receiving a response"
        )
        XCTAssertFalse(sess.emittedEvents.contains { event in
            if case .turnStarted = event { return true }
            return false
        })
    }

    func testDynamicToolResponseDoesNothingWhenNobodyIsWaiting() async throws {
        let sess = Session()
        _ = try await sess.submit(
            .dynamicToolResponse(
                id: "missing",
                response: DynamicToolResponse(contentItems: [.inputText(text: "found")], success: true)
            )
        )
        XCTAssertNil(sess.activeTurn)
        XCTAssertNil(sess.lastStartedTurnId)
        XCTAssertFalse(sess.emittedEvents.contains { event in
            if case .turnStarted = event { return true }
            return false
        })
    }

    func testResolveElicitationResumesTheWaitingRequest() async throws {
        let sess = Session()
        let turn = TurnContext(subId: "turn-elicit")
        sess.activeTurn = ActiveTurn(task: RunningTask(kind: .regular, turnContext: turn))
        let request = ElicitationRequest.url(
            meta: nil,
            message: "Connect this app to continue.",
            url: "https://example.com/connect",
            elicitationId: "connect-1"
        )
        let pending = Task {
            await sess.requestMcpServerElicitation(
                turnContext: turn,
                serverName: "codex_apps",
                requestId: .string("request-1"),
                request: request
            )
        }
        try await waitUntil { elicitationRequests(in: sess).count == 1 }
        let event = try XCTUnwrap(elicitationRequests(in: sess).first)
        XCTAssertEqual(event.turnId, "turn-elicit")
        XCTAssertEqual(event.serverName, "codex_apps")
        XCTAssertEqual(event.id, .string("request-1"))
        XCTAssertEqual(event.request, request)
        let paused = await elicitationIsPaused(sess)
        XCTAssertTrue(paused)
        let response = ElicitationResponse(action: .accept, content: .object(["ok": .bool(true)]))
        await sess.resolveElicitation(
            serverName: "codex_apps", id: .string("request-1"), response: response)
        let outcome = await pending.value
        XCTAssertEqual(outcome.response, response)
        XCTAssertTrue(outcome.sent)
        let stillPaused = await elicitationIsPaused(sess)
        XCTAssertFalse(stillPaused)
        XCTAssertNil(sess.lastStartedTurnId)
    }

    func testResolveElicitationFillsAcceptContentAndDropsDeclineContent() async throws {
        let sess = Session()
        let turn = TurnContext(subId: "turn-elicit")
        sess.activeTurn = ActiveTurn(task: RunningTask(kind: .regular, turnContext: turn))
        let request = ElicitationRequest.form(
            meta: nil, message: "Allow?", requestedSchema: .object([:]))
        let pending = Task {
            await sess.requestMcpServerElicitation(
                turnContext: turn,
                serverName: "codex_apps",
                requestId: .integer(7),
                request: request
            )
        }
        try await waitUntil { elicitationRequests(in: sess).count == 1 }
        _ = try await sess.submit(
            .resolveElicitation(
                serverName: "codex_apps",
                requestId: .integer(7),
                decision: .accept,
                content: nil,
                meta: .object(["source": .string("hud")])
            )
        )
        let accepted = await pending.value
        XCTAssertEqual(accepted.response?.action, .accept)
        XCTAssertEqual(accepted.response?.content, .object([:]))
        XCTAssertEqual(accepted.response?.meta, .object(["source": .string("hud")]))
        XCTAssertNil(sess.lastStartedTurnId)
        XCTAssertFalse(sess.emittedEvents.contains { event in
            if case .turnStarted = event { return true }
            return false
        })

        let declined = Task {
            await sess.requestMcpServerElicitation(
                turnContext: turn,
                serverName: "codex_apps",
                requestId: .string("decline"),
                request: request
            )
        }
        try await waitUntil { elicitationRequests(in: sess).count == 2 }
        _ = try await sess.submit(
            .resolveElicitation(
                serverName: "codex_apps",
                requestId: .string("decline"),
                decision: .decline,
                content: .object(["reason": .string("no")]),
                meta: nil
            )
        )
        let outcome = await declined.value
        XCTAssertEqual(outcome.response?.action, .decline)
        XCTAssertNil(outcome.response?.content)
    }

    func testResolveElicitationAutoDenySkipsTheRequest() async {
        let sess = Session()
        sess.services.mcpRuntime.elicitationsAutoDeny = true
        let turn = TurnContext(subId: "turn-elicit")
        sess.activeTurn = ActiveTurn(task: RunningTask(kind: .regular, turnContext: turn))
        let outcome = await sess.requestMcpServerElicitation(
            turnContext: turn,
            serverName: "codex_apps",
            requestId: .string("request-1"),
            request: ElicitationRequest.form(
                meta: nil, message: "Allow?", requestedSchema: .object([:]))
        )
        XCTAssertEqual(
            outcome.response,
            ElicitationResponse(action: .accept, content: .object([:]))
        )
        XCTAssertFalse(outcome.sent)
        XCTAssertTrue(elicitationRequests(in: sess).isEmpty)
        let paused = await elicitationIsPaused(sess)
        XCTAssertFalse(paused)
    }

    func testResolveElicitationWithoutATurnStillEmitsTheRequest() async {
        let sess = Session()
        let turn = TurnContext(subId: "turn-idle")
        let outcome = await sess.requestMcpServerElicitation(
            turnContext: turn,
            serverName: "codex_apps",
            requestId: .string("request-1"),
            request: ElicitationRequest.url(
                meta: nil, message: "Connect", url: "https://example.com", elicitationId: "c1")
        )
        XCTAssertNil(outcome.response)
        XCTAssertTrue(outcome.sent)
        XCTAssertEqual(elicitationRequests(in: sess).count, 1)
        XCTAssertNil(sess.activeTurn)
        let paused = await elicitationIsPaused(sess)
        XCTAssertFalse(paused)
    }

    func testResolveElicitationReplacesThePreviousWaiter() async throws {
        let sess = Session()
        let turn = TurnContext(subId: "turn-elicit")
        sess.activeTurn = ActiveTurn(task: RunningTask(kind: .regular, turnContext: turn))
        let request = ElicitationRequest.form(
            meta: nil, message: "Allow?", requestedSchema: .object([:]))
        let first = Task {
            await sess.requestMcpServerElicitation(
                turnContext: turn,
                serverName: "codex_apps",
                requestId: .string("request-1"),
                request: request
            )
        }
        try await waitUntil { elicitationRequests(in: sess).count == 1 }
        let second = Task {
            await sess.requestMcpServerElicitation(
                turnContext: turn,
                serverName: "codex_apps",
                requestId: .string("request-1"),
                request: request
            )
        }
        let replaced = await first.value
        XCTAssertNil(replaced.response)
        XCTAssertTrue(replaced.sent)
        try await waitUntil { elicitationRequests(in: sess).count == 2 }
        await sess.resolveElicitation(
            serverName: "codex_apps",
            id: .string("request-1"),
            response: ElicitationResponse(action: .cancel)
        )
        let outcome = await second.value
        XCTAssertEqual(outcome.response?.action, .cancel)
        XCTAssertNil(outcome.response?.content)
    }

    func testResolveElicitationFallsBackWhenNobodyIsWaiting() async throws {
        let sess = Session()
        let seen = expectation(description: "fallback")
        sess.services.mcpRuntime.resolveElicitationFallback = { server, id, response in
            XCTAssertEqual(server, "codex_apps")
            XCTAssertEqual(id, .string("missing"))
            XCTAssertEqual(response.action, .cancel)
            XCTAssertNil(response.content)
            seen.fulfill()
        }
        _ = try await sess.submit(
            .resolveElicitation(
                serverName: "codex_apps",
                requestId: .string("missing"),
                decision: .cancel,
                content: .object(["ignored": .bool(true)]),
                meta: nil
            )
        )
        await fulfillment(of: [seen], timeout: 1)
        XCTAssertNil(sess.activeTurn)
        XCTAssertNil(sess.lastStartedTurnId)
    }

    func testDynamicToolHandlerWaitsForDynamicToolResponse() async throws {
        let sess = Session()
        let entered = expectation(description: "sampling")
        let gate = SubmissionAck()
        defer {
            sess.activeTurn?.turnState.clearPendingWaiters()
            gate.signal()
        }
        sess.runSamplingOverride = { _, _ in
            entered.fulfill()
            await gate.wait()
            return SamplingRequestResult(needsFollowUp: false, lastAgentMessage: "kept")
        }
        _ = try await sess.submit(
            .userInput(TurnInputBuilder.user([.text(text: "hello", textElements: [])]))
        )
        await fulfillment(of: [entered], timeout: 1)
        let live = try XCTUnwrap(sess.activeTurn?.task?.turnContext)
        let started = sess.emittedEvents.filter { event in
            if case .turnStarted = event { return true }
            return false
        }.count
        let toolName = ToolName(namespace: "docs", name: "lookup")
        let handler = try XCTUnwrap(
            DynamicToolHandler(
                DynamicToolFunctionSpec(
                    name: "lookup",
                    description: "Look up",
                    inputSchema: .object([:])
                ),
                namespace: DynamicToolNamespaceSpec(name: "docs", description: "Docs")
            )
        )
        var registry = HarnessToolRegistry()
        registry.register(handler)
        let step = StepContext(
            turn: live,
            toolRouter: ToolRouter(
                registry: registry,
                modelVisibleSpecs: [],
                toolMode: .direct,
                canManageChildren: false
            )
        )
        let outputTask = Task {
            try await ToolCallRuntime(session: sess, stepContext: step).handleToolCall(
                ToolCall(
                    toolName: toolName,
                    callId: "call-dyn",
                    payload: .function(arguments: #"{"q":"sage"}"#)
                ),
                cancellationToken: CancellationToken()
            )
        }
        try await waitUntil {
            dynamicToolCalls(in: sess, callId: "call-dyn", status: .inProgress).count == 1
        }
        let inProgress = try XCTUnwrap(
            dynamicToolCalls(in: sess, callId: "call-dyn", status: .inProgress).first)
        XCTAssertEqual(inProgress.namespace, "docs")
        XCTAssertEqual(inProgress.tool, "lookup")
        XCTAssertEqual(inProgress.arguments, .object(["q": .string("sage")]))
        let found = DynamicToolResponse(
            contentItems: [.inputText(text: "found")], success: true)
        _ = try await sess.submit(.dynamicToolResponse(id: "call-dyn", response: found))
        let output = try await outputTask.value
        guard case .functionCallOutput(_, let callId, _, _, let payload, _) = output else {
            return XCTFail("expected function call output")
        }
        XCTAssertEqual(callId, "call-dyn")
        XCTAssertEqual(payload.body.toText(), "found")
        XCTAssertEqual(payload.success, true)
        let completed = try XCTUnwrap(
            dynamicToolCalls(in: sess, callId: "call-dyn", status: .completed).first)
        XCTAssertEqual(completed.contentItems, [.inputText(text: "found")])
        XCTAssertEqual(completed.success, true)
        XCTAssertEqual(
            sess.emittedEvents.filter { event in
                if case .turnStarted = event { return true }
                return false
            }.count,
            started
        )
        gate.signal()
        await sess.waitUntilIdle()
        XCTAssertEqual(sess.lastTaskAgentMessage, "kept")
        XCTAssertEqual(sess.lastStartedTurnId, live.subId)
    }

    func testDynamicToolHandlerWithoutATurnReturnsCancelled() async throws {
        let sess = Session()
        let handler = try XCTUnwrap(
            DynamicToolHandler(
                DynamicToolFunctionSpec(
                    name: "lookup",
                    description: "Look up",
                    inputSchema: .object([:])
                )
            )
        )
        var registry = HarnessToolRegistry()
        registry.register(handler)
        let step = StepContext(
            toolRouter: ToolRouter(
                registry: registry,
                modelVisibleSpecs: [],
                toolMode: .direct,
                canManageChildren: false
            )
        )
        let output = try await ToolCallRuntime(session: sess, stepContext: step).handleToolCall(
            ToolCall(
                toolName: ToolName(plain: "lookup"),
                callId: "call-idle",
                payload: .function(arguments: "{}")
            ),
            cancellationToken: CancellationToken()
        )
        guard case .functionCallOutput(_, let callId, _, _, let payload, _) = output else {
            return XCTFail("expected function call output")
        }
        XCTAssertEqual(callId, "call-idle")
        XCTAssertEqual(
            payload.body.toText(),
            "dynamic tool call was cancelled before receiving a response"
        )
        XCTAssertEqual(
            dynamicToolCalls(in: sess, callId: "call-idle", status: .inProgress).count, 1)
        XCTAssertEqual(
            dynamicToolCalls(in: sess, callId: "call-idle", status: .failed).first?.error,
            "dynamic tool call was cancelled before receiving a response"
        )
        XCTAssertNil(sess.activeTurn)
        XCTAssertNil(sess.lastStartedTurnId)
    }

    func testExecApprovalResumesTheWaitingCommand() async throws {
        let sess = Session()
        let entered = expectation(description: "sampling")
        let gate = SubmissionAck()
        defer {
            sess.activeTurn?.turnState.clearPendingWaiters()
            gate.signal()
        }
        sess.runSamplingOverride = { _, _ in
            entered.fulfill()
            await gate.wait()
            return SamplingRequestResult(needsFollowUp: false, lastAgentMessage: "kept")
        }
        _ = try await sess.submit(
            .userInput(TurnInputBuilder.user([.text(text: "hello", textElements: [])]))
        )
        await fulfillment(of: [entered], timeout: 1)
        let turn = try XCTUnwrap(sess.activeTurn?.task?.turnContext)
        let startedTurns = sess.emittedEvents.filter { event in
            if case .turnStarted = event { return true }
            return false
        }.count
        let command = ["git", "status"]
        let cwd = FileManager.default.currentDirectoryPath

        let approved = Task {
            await sess.requestCommandApproval(
                turnContext: turn,
                request: CommandApprovalRequest(
                    callId: "call-9", approvalId: "step-1", command: command, cwd: cwd,
                    reason: "status")
            )
        }
        try await waitUntil { execApprovalRequests(in: sess, callId: "call-9").count == 1 }
        let requested = try XCTUnwrap(execApprovalRequests(in: sess, callId: "call-9").first)
        XCTAssertEqual(requested.approvalId, "step-1")
        XCTAssertEqual(requested.turnId, turn.subId)
        XCTAssertEqual(requested.command, command)
        XCTAssertEqual(requested.reason, "status")
        XCTAssertEqual(requested.parsedCmd, parseCommand(command))
        XCTAssertEqual(
            requested.availableDecisions,
            [CodexProtocol.ReviewDecision.approved, .abort]
        )
        _ = try await sess.submit(
            .execApproval(id: "call-9", turnId: turn.subId, decision: .approved)
        )
        XCTAssertEqual(sess.activeTurn?.task?.turnContext.subId, turn.subId)
        _ = try await sess.submit(
            .execApproval(id: "step-1", turnId: turn.subId, decision: .approved)
        )
        let accepted = await approved.value
        XCTAssertEqual(accepted, .approved)

        let first = Task {
            await sess.requestCommandApproval(
                turnContext: turn,
                request: CommandApprovalRequest(callId: "call-1", command: command, cwd: cwd)
            )
        }
        try await waitUntil { execApprovalRequests(in: sess, callId: "call-1").count == 1 }
        let second = Task {
            await sess.requestCommandApproval(
                turnContext: turn,
                request: CommandApprovalRequest(callId: "call-1", command: command, cwd: cwd)
            )
        }
        try await waitUntil { execApprovalRequests(in: sess, callId: "call-1").count == 2 }
        _ = try await sess.submit(
            .execApproval(
                id: "call-1", turnId: turn.subId,
                decision: .denied(rejection: "no"))
        )
        let replacement = await second.value
        let replaced = await first.value
        XCTAssertEqual(replacement, .denied(rejection: "no"))
        XCTAssertEqual(replaced, .abort)

        let amendment = CodexProtocol.ReviewDecision.approvedExecpolicyAmendment(
            proposedExecpolicyAmendment: ExecPolicyAmendment(["ls"]))
        let unwired = Task {
            await sess.requestCommandApproval(
                turnContext: turn,
                request: CommandApprovalRequest(callId: "call-amend", command: ["ls"], cwd: cwd)
            )
        }
        try await waitUntil { execApprovalRequests(in: sess, callId: "call-amend").count == 1 }
        _ = try await sess.submit(
            .execApproval(id: "call-amend", turnId: turn.subId, decision: amendment)
        )
        let unwiredDecision = await unwired.value
        XCTAssertEqual(unwiredDecision, amendment)
        XCTAssertTrue(sess.emittedEvents.contains { event in
            if case .warning(let warning) = event {
                return warning.message ==
                    "Failed to apply execpolicy amendment: exec policy is not configured"
            }
            return false
        })

        let policyHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("sage-execpolicy-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: policyHome) }
        sess.state.sessionConfiguration.codexHome = policyHome.path
        sess.services.execPolicy = Policy()
        let saved = Task {
            await sess.requestCommandApproval(
                turnContext: turn,
                request: CommandApprovalRequest(callId: "call-saved", command: ["ls"], cwd: cwd)
            )
        }
        try await waitUntil { execApprovalRequests(in: sess, callId: "call-saved").count == 1 }
        let warnings = sess.emittedEvents.filter { event in
            if case .warning = event { return true }
            return false
        }.count
        _ = try await sess.submit(
            .execApproval(id: "call-saved", turnId: turn.subId, decision: amendment)
        )
        let savedDecision = await saved.value
        XCTAssertEqual(savedDecision, amendment)
        XCTAssertEqual(
            sess.emittedEvents.filter { event in
                if case .warning = event { return true }
                return false
            }.count,
            warnings
        )
        XCTAssertEqual(sess.services.execPolicy?.getAllowedPrefixes(), [["ls"]])
        let policyFile = policyHome
            .appendingPathComponent("rules", isDirectory: true)
            .appendingPathComponent("default.rules")
        let policyText = try String(contentsOf: policyFile, encoding: .utf8)
        XCTAssertEqual(policyText, "prefix_rule(pattern=[\"ls\"], decision=\"allow\")\n")

        let again = Task {
            await sess.requestCommandApproval(
                turnContext: turn,
                request: CommandApprovalRequest(callId: "call-again", command: ["ls"], cwd: cwd)
            )
        }
        try await waitUntil { execApprovalRequests(in: sess, callId: "call-again").count == 1 }
        _ = try await sess.submit(
            .execApproval(id: "call-again", turnId: turn.subId, decision: amendment)
        )
        let againDecision = await again.value
        XCTAssertEqual(againDecision, amendment)
        XCTAssertEqual(sess.services.execPolicy?.getAllowedPrefixes(), [["ls"]])
        XCTAssertEqual(try String(contentsOf: policyFile, encoding: .utf8), policyText)

        let empty = Task {
            await sess.requestCommandApproval(
                turnContext: turn,
                request: CommandApprovalRequest(callId: "call-empty", command: ["ls"], cwd: cwd)
            )
        }
        try await waitUntil { execApprovalRequests(in: sess, callId: "call-empty").count == 1 }
        _ = try await sess.submit(
            .execApproval(
                id: "call-empty",
                turnId: turn.subId,
                decision: .approvedExecpolicyAmendment(
                    proposedExecpolicyAmendment: ExecPolicyAmendment([])
                )
            )
        )
        let emptyDecision = await empty.value
        XCTAssertEqual(emptyDecision, .approvedExecpolicyAmendment(
            proposedExecpolicyAmendment: ExecPolicyAmendment([])))
        XCTAssertTrue(sess.emittedEvents.contains { event in
            if case .warning(let warning) = event {
                return warning.message.contains("prefix rule requires at least one token")
            }
            return false
        })
        XCTAssertEqual(sess.services.execPolicy?.getAllowedPrefixes(), [["ls"]])
        XCTAssertEqual(try String(contentsOf: policyFile, encoding: .utf8), policyText)

        XCTAssertFalse(sess.emittedEvents.contains { event in
            if case .turnAborted = event { return true }
            return false
        })
        XCTAssertEqual(
            sess.emittedEvents.filter { event in
                if case .turnStarted = event { return true }
                return false
            }.count,
            startedTurns
        )
        gate.signal()
        await sess.waitUntilIdle()
        XCTAssertEqual(sess.lastTaskAgentMessage, "kept")
        XCTAssertEqual(sess.lastStartedTurnId, turn.subId)
    }

    func testExecApprovalAbortInterruptsTheTurn() async throws {
        let sess = Session()
        let entered = expectation(description: "sampling")
        let gate = SubmissionAck()
        defer {
            sess.activeTurn?.turnState.clearPendingWaiters()
            gate.signal()
        }
        sess.runSamplingOverride = { _, _ in
            entered.fulfill()
            await gate.wait()
            return SamplingRequestResult(needsFollowUp: false, lastAgentMessage: "kept")
        }
        _ = try await sess.submit(
            .userInput(TurnInputBuilder.user([.text(text: "hello", textElements: [])]))
        )
        await fulfillment(of: [entered], timeout: 1)
        let turn = try XCTUnwrap(sess.activeTurn?.task?.turnContext)
        let waiting = Task {
            await sess.requestCommandApproval(
                turnContext: turn,
                request: CommandApprovalRequest(
                    callId: "call-abort",
                    command: ["git", "status"],
                    cwd: FileManager.default.currentDirectoryPath
                )
            )
        }
        try await waitUntil { execApprovalRequests(in: sess, callId: "call-abort").count == 1 }
        _ = try await sess.submit(
            .execApproval(id: "missing", turnId: turn.subId, decision: .abort)
        )
        let decision = await waiting.value
        XCTAssertEqual(decision, .abort)
        XCTAssertNil(sess.activeTurn)
        XCTAssertTrue(sess.emittedEvents.contains { event in
            if case .turnAborted(let aborted) = event {
                return aborted.turnId == turn.subId && aborted.reason == .interrupted
            }
            return false
        })
        XCTAssertEqual(sess.lastStartedTurnId, turn.subId)
        gate.signal()
    }

    func testExecApprovalWithoutATurnReturnsAbort() async {
        let sess = Session()
        let turn = TurnContext(subId: "turn-idle")
        let decision = await sess.requestCommandApproval(
            turnContext: turn,
            request: CommandApprovalRequest(
                callId: "call-idle", command: ["ls"], cwd: "/tmp")
        )
        XCTAssertEqual(decision, .abort)
        XCTAssertNil(sess.activeTurn)
        XCTAssertEqual(execApprovalRequests(in: sess, callId: "call-idle").count, 1)
        XCTAssertFalse(sess.emittedEvents.contains { event in
            if case .turnStarted = event { return true }
            return false
        })
    }

    func testExecApprovalDoesNothingWhenNobodyIsWaiting() async throws {
        let sess = Session()
        _ = try await sess.submit(
            .execApproval(id: "missing", turnId: nil, decision: .approved)
        )
        XCTAssertNil(sess.activeTurn)
        XCTAssertNil(sess.lastStartedTurnId)
        XCTAssertFalse(sess.emittedEvents.contains { event in
            if case .turnStarted = event { return true }
            return false
        })
        XCTAssertFalse(sess.emittedEvents.contains { event in
            if case .turnAborted = event { return true }
            return false
        })
    }

    func testPatchApprovalResumesTheWaitingCall() async throws {
        let sess = Session()
        let entered = expectation(description: "sampling")
        let gate = SubmissionAck()
        defer {
            sess.activeTurn?.turnState.clearPendingWaiters()
            gate.signal()
        }
        sess.runSamplingOverride = { _, _ in
            entered.fulfill()
            await gate.wait()
            return SamplingRequestResult(needsFollowUp: false, lastAgentMessage: "kept")
        }
        _ = try await sess.submit(
            .userInput(TurnInputBuilder.user([.text(text: "hello", textElements: [])]))
        )
        await fulfillment(of: [entered], timeout: 1)
        let turn = try XCTUnwrap(sess.activeTurn?.task?.turnContext)
        let startedTurns = sess.emittedEvents.filter { event in
            if case .turnStarted = event { return true }
            return false
        }.count
        let changes = ["src/main.swift": FileChange.add(content: "print(1)\n")]

        let approved = Task {
            await sess.requestPatchApproval(
                turnContext: turn, callId: "call-1", changes: changes,
                reason: "add main", grantRoot: "/tmp/workspace")
        }
        try await waitUntil { patchApprovalRequests(in: sess, callId: "call-1").count == 1 }
        let requested = try XCTUnwrap(patchApprovalRequests(in: sess, callId: "call-1").first)
        XCTAssertEqual(requested.turnId, turn.subId)
        XCTAssertEqual(requested.changes, changes)
        XCTAssertEqual(requested.reason, "add main")
        XCTAssertEqual(requested.grantRoot, "/tmp/workspace")
        _ = try await sess.submit(.patchApproval(id: "missing", decision: .approved))
        XCTAssertEqual(sess.activeTurn?.task?.turnContext.subId, turn.subId)
        _ = try await sess.submit(.patchApproval(id: "call-1", decision: .approved))
        let accepted = await approved.value
        XCTAssertEqual(accepted, .approved)

        let command = Task {
            await sess.requestCommandApproval(
                turnContext: turn,
                request: CommandApprovalRequest(
                    callId: "shared", command: ["ls"], cwd: "/tmp")
            )
        }
        try await waitUntil { execApprovalRequests(in: sess, callId: "shared").count == 1 }
        let patch = Task {
            await sess.requestPatchApproval(
                turnContext: turn, callId: "shared", changes: changes, reason: nil, grantRoot: nil)
        }
        try await waitUntil { patchApprovalRequests(in: sess, callId: "shared").count == 1 }
        _ = try await sess.submit(
            .patchApproval(id: "shared", decision: .approvedForSession)
        )
        let patchDecision = await patch.value
        let commandDecision = await command.value
        XCTAssertEqual(patchDecision, .approvedForSession)
        XCTAssertEqual(commandDecision, .abort)

        XCTAssertFalse(sess.emittedEvents.contains { event in
            if case .turnAborted = event { return true }
            return false
        })
        XCTAssertEqual(
            sess.emittedEvents.filter { event in
                if case .turnStarted = event { return true }
                return false
            }.count,
            startedTurns
        )
        gate.signal()
        await sess.waitUntilIdle()
        XCTAssertEqual(sess.lastTaskAgentMessage, "kept")
        XCTAssertEqual(sess.lastStartedTurnId, turn.subId)
    }

    func testPatchApprovalAbortInterruptsTheTurn() async throws {
        let sess = Session()
        let entered = expectation(description: "sampling")
        let gate = SubmissionAck()
        defer {
            sess.activeTurn?.turnState.clearPendingWaiters()
            gate.signal()
        }
        sess.runSamplingOverride = { _, _ in
            entered.fulfill()
            await gate.wait()
            return SamplingRequestResult(needsFollowUp: false, lastAgentMessage: "kept")
        }
        _ = try await sess.submit(
            .userInput(TurnInputBuilder.user([.text(text: "hello", textElements: [])]))
        )
        await fulfillment(of: [entered], timeout: 1)
        let turn = try XCTUnwrap(sess.activeTurn?.task?.turnContext)
        let waiting = Task {
            await sess.requestPatchApproval(
                turnContext: turn,
                callId: "call-abort",
                changes: ["src/main.swift": .add(content: "print(1)\n")],
                reason: nil,
                grantRoot: nil
            )
        }
        try await waitUntil { patchApprovalRequests(in: sess, callId: "call-abort").count == 1 }
        _ = try await sess.submit(.patchApproval(id: "missing", decision: .abort))
        let decision = await waiting.value
        XCTAssertEqual(decision, .abort)
        XCTAssertNil(sess.activeTurn)
        XCTAssertTrue(sess.emittedEvents.contains { event in
            if case .turnAborted(let aborted) = event {
                return aborted.turnId == turn.subId && aborted.reason == .interrupted
            }
            return false
        })
        XCTAssertEqual(sess.lastStartedTurnId, turn.subId)
        gate.signal()
    }

    func testPatchApprovalWithoutATurnReturnsAbort() async {
        let sess = Session()
        let turn = TurnContext(subId: "turn-idle")
        let decision = await sess.requestPatchApproval(
            turnContext: turn,
            callId: "call-idle",
            changes: ["src/main.swift": .add(content: "print(1)\n")],
            reason: nil,
            grantRoot: nil
        )
        XCTAssertEqual(decision, .abort)
        XCTAssertNil(sess.activeTurn)
        XCTAssertEqual(patchApprovalRequests(in: sess, callId: "call-idle").count, 1)
        XCTAssertFalse(sess.emittedEvents.contains { event in
            if case .turnStarted = event { return true }
            return false
        })
    }

    func testPatchApprovalDoesNothingWhenNobodyIsWaiting() async throws {
        let sess = Session()
        _ = try await sess.submit(.patchApproval(id: "missing", decision: .approved))
        XCTAssertNil(sess.activeTurn)
        XCTAssertNil(sess.lastStartedTurnId)
        XCTAssertFalse(sess.emittedEvents.contains { event in
            if case .turnStarted = event { return true }
            return false
        })
        XCTAssertFalse(sess.emittedEvents.contains { event in
            if case .turnAborted = event { return true }
            return false
        })
    }

    func testRefreshMcpServersMarksTheNextRefresh() async throws {
        let sess = Session()
        _ = try await sess.submit(.refreshMcpServers)
        try await waitUntil { sess.services.mcpRuntime.publishCount == 1 }
        XCTAssertFalse(sess.services.mcpRuntime.reconnectPending)
        XCTAssertFalse(sess.services.mcpRuntime.dirty)
        XCTAssertFalse(sess.mcpPrewarmRequested)
        XCTAssertFalse(sess.mcpRefresh.isPending)
        XCTAssertEqual(sess.services.mcpRuntime.resourceCacheGeneration, 1)
        XCTAssertEqual(sess.services.mcpRuntime.reconnectedPublishCount, 1)
        XCTAssertTrue(sess.services.mcpRuntime.lastPublishReconnected)
        XCTAssertTrue(sess.mcpReprojectionRequested)
        XCTAssertNil(sess.activeTurn)
        XCTAssertNil(sess.lastStartedTurnId)
        _ = try await sess.submit(.refreshMcpServers)
        try await waitUntil { sess.services.mcpRuntime.publishCount == 2 }
        XCTAssertFalse(sess.services.mcpRuntime.reconnectPending)
        XCTAssertEqual(sess.services.mcpRuntime.resourceCacheGeneration, 2)
        XCTAssertEqual(sess.services.mcpRuntime.reconnectedPublishCount, 2)
        XCTAssertFalse(sess.emittedEvents.contains { event in
            if case .turnStarted = event { return true }
            return false
        })
    }

    func testRefreshMcpServersCoalescesWhileAPublishIsInFlight() async throws {
        let sess = Session()
        let gate = SubmissionAck()
        defer { gate.signal() }
        sess.services.mcpRuntime.publishHook = {
            await gate.wait()
        }
        _ = try await sess.submit(.refreshMcpServers)
        try await waitUntil { sess.services.mcpRuntime.publishAttempts == 1 }
        XCTAssertEqual(sess.services.mcpRuntime.publishCount, 0)
        XCTAssertTrue(sess.services.mcpRuntime.reconnectPending)
        XCTAssertEqual(sess.services.mcpRuntime.resourceCacheGeneration, 1)
        _ = try await sess.submit(.refreshMcpServers)
        XCTAssertEqual(sess.services.mcpRuntime.resourceCacheGeneration, 2)
        XCTAssertTrue(sess.mcpRefresh.isPending)
        XCTAssertEqual(sess.services.mcpRuntime.publishAttempts, 1)
        gate.signal()
        try await waitUntil {
            sess.services.mcpRuntime.publishCount == 2 && !sess.mcpPrewarmRequested
                && !sess.mcpRefresh.isPending
        }
        XCTAssertFalse(sess.services.mcpRuntime.reconnectPending)
        XCTAssertFalse(sess.services.mcpRuntime.dirty)
        XCTAssertGreaterThan(sess.services.mcpRuntime.reconnectedPublishCount, 0)
        XCTAssertNil(sess.activeTurn)
    }

    func testMcpPublishRebuildsTheBindingFromTheCurrentConfig() async throws {
        let sess = Session()
        sess.state.sessionConfiguration.originalConfig.mcpServers = [
            "old": ConfiguredMcpServer(url: "https://old.example/mcp", enabled: true)
        ]
        sess.state.sessionConfiguration.originalConfig.approvalPolicy = .onRequest
        sess.services.mcpVisibleTools = [McpVisibleTool(name: "old_tool", serverName: "old")]
        let turn = sess.newTurnContext()
        sess.markMcpRuntimeDirty()
        let oldStep = try await sess.captureStepContext(
            turn, cancellationToken: CancellationToken())
        let oldBinding = try XCTUnwrap(oldStep.mcp)
        XCTAssertEqual(oldBinding.servers["old"]?.url, "https://old.example/mcp")
        XCTAssertNil(oldBinding.servers["refreshed"])
        XCTAssertEqual(oldBinding.tools.map(\.name), ["old_tool"])
        XCTAssertEqual(oldBinding.approvalPolicy, .onRequest)
        XCTAssertEqual(oldBinding.permissionProfile, .readOnly())

        sess.state.sessionConfiguration.originalConfig.mcpServers["refreshed"] = ConfiguredMcpServer(
            url: "https://refreshed.example/mcp",
            enabled: false
        )
        sess.state.sessionConfiguration.originalConfig.approvalPolicy = .never
        sess.state.sessionConfiguration.originalConfig.permissions.permissionProfile = .disabled
        sess.services.mcpVisibleTools = [McpVisibleTool(name: "new_tool", serverName: "refreshed")]
        sess.markMcpRuntimeDirty()
        let newStep = try await sess.captureStepContext(
            turn, cancellationToken: CancellationToken())
        let newBinding = try XCTUnwrap(newStep.mcp)
        XCTAssertFalse(oldBinding === newBinding)
        XCTAssertNil(oldBinding.servers["refreshed"])
        XCTAssertEqual(oldBinding.approvalPolicy, .onRequest)
        XCTAssertEqual(oldBinding.tools.map(\.name), ["old_tool"])
        XCTAssertEqual(newBinding.servers["refreshed"]?.url, "https://refreshed.example/mcp")
        XCTAssertEqual(newBinding.servers["refreshed"]?.enabled, false)
        XCTAssertEqual(newBinding.servers["old"]?.url, "https://old.example/mcp")
        XCTAssertEqual(newBinding.approvalPolicy, .never)
        XCTAssertEqual(newBinding.permissionProfile, .disabled)
        XCTAssertEqual(newBinding.tools.map(\.name), ["new_tool"])
        XCTAssertTrue(sess.services.mcpRuntime.currentBinding === newBinding)
        XCTAssertEqual(sess.services.mcpBindingID, newBinding.id)
        XCTAssertNil(turn.config.mcpServers["refreshed"])
        XCTAssertEqual(turn.approvalPolicy, .onRequest)

        let again = try await sess.captureStepContext(
            turn, cancellationToken: CancellationToken())
        XCTAssertTrue(again.mcp === newBinding)
        XCTAssertNil(sess.activeTurn)
    }

    func testMcpAuthChangePublishesWithoutReconnect() async throws {
        let sess = Session()
        sess.state.sessionConfiguration.originalConfig.mcpServers = [
            "old": ConfiguredMcpServer(url: "https://old.example/mcp", enabled: true)
        ]
        sess.noteMcpAuthChanged()
        try await waitUntil { sess.services.mcpRuntime.publishCount == 1 }
        XCTAssertEqual(sess.services.mcpRuntime.resourceCacheGeneration, 0)
        XCTAssertFalse(sess.services.mcpRuntime.reconnectPending)
        XCTAssertFalse(sess.services.mcpRuntime.dirty)
        XCTAssertFalse(sess.mcpPrewarmRequested)
        XCTAssertEqual(
            sess.services.mcpRuntime.currentBinding?.servers["old"]?.url,
            "https://old.example/mcp"
        )
        XCTAssertNil(sess.activeTurn)

        let gate = SubmissionAck()
        defer { gate.signal() }
        sess.services.mcpRuntime.publishHook = {
            await gate.wait()
        }
        sess.noteMcpAuthChanged()
        try await waitUntil { sess.services.mcpRuntime.publishAttempts == 2 }
        XCTAssertEqual(sess.services.mcpRuntime.publishCount, 1)
        sess.state.sessionConfiguration.originalConfig.mcpServers["later"] = ConfiguredMcpServer(
            url: "https://later.example/mcp",
            enabled: true
        )
        sess.noteMcpAuthChanged()
        XCTAssertEqual(sess.services.mcpRuntime.publishAttempts, 2)
        gate.signal()
        try await waitUntil {
            sess.services.mcpRuntime.publishCount == 3
                && sess.services.mcpRuntime.currentBinding?.servers["later"] != nil
                && !sess.mcpRefresh.isPending
        }
        XCTAssertEqual(sess.services.mcpRuntime.resourceCacheGeneration, 0)
        XCTAssertFalse(sess.services.mcpRuntime.reconnectPending)
        XCTAssertEqual(
            sess.services.mcpRuntime.currentBinding?.servers["later"]?.url,
            "https://later.example/mcp"
        )
        XCTAssertNil(sess.activeTurn)
    }

    func testMcpPublishReusesConnectionsUntilReconnect() async throws {
        let sess = Session()
        let log = McpConnectLog()
        sess.services.ensureMcpConnected = { log.ensure() }
        sess.services.reconnectMcp = { log.reconnect() }
        sess.services.disconnectMcp = { names in log.disconnect(names) }
        sess.state.sessionConfiguration.originalConfig.mcpServers = [
            "old": ConfiguredMcpServer(url: "https://old.example/mcp", enabled: true),
            "off": ConfiguredMcpServer(url: "https://off.example/mcp", enabled: false),
        ]
        let turn = sess.newTurnContext()
        sess.markMcpRuntimeDirty()
        let first = try await sess.captureStepContext(
            turn, cancellationToken: CancellationToken())
        let firstConnection = try XCTUnwrap(first.mcp?.connections["old"])
        XCTAssertEqual(firstConnection.url, "https://old.example/mcp")
        XCTAssertNil(first.mcp?.connections["off"])
        XCTAssertEqual(log.ensured, 1)
        XCTAssertEqual(log.reconnected, 0)

        sess.markMcpRuntimeDirty()
        let reused = try await sess.captureStepContext(
            turn, cancellationToken: CancellationToken())
        XCTAssertTrue(reused.mcp?.connections["old"] === firstConnection)
        XCTAssertEqual(log.ensured, 1)
        XCTAssertEqual(log.reconnected, 0)

        sess.state.sessionConfiguration.originalConfig.mcpServers["old"] = ConfiguredMcpServer(
            url: "https://moved.example/mcp",
            enabled: true
        )
        sess.markMcpRuntimeDirty()
        let moved = try await sess.captureStepContext(
            turn, cancellationToken: CancellationToken())
        let movedConnection = try XCTUnwrap(moved.mcp?.connections["old"])
        XCTAssertFalse(movedConnection === firstConnection)
        XCTAssertEqual(movedConnection.url, "https://moved.example/mcp")
        XCTAssertEqual(log.ensured, 2)
        XCTAssertEqual(log.reconnected, 0)

        _ = try await sess.submit(.refreshMcpServers)
        try await waitUntil {
            guard sess.services.mcpRuntime.reconnectedPublishCount >= 1,
                  let current = sess.services.mcpRuntime.currentBinding?.connections["old"]
            else { return false }
            return current !== movedConnection
        }
        XCTAssertEqual(log.reconnected, 1)
        XCTAssertEqual(log.ensured, 2)
        XCTAssertEqual(log.disconnected, [])
        XCTAssertNil(sess.services.mcpRuntime.currentBinding?.connections["off"])
        XCTAssertNil(sess.activeTurn)
    }

    func testMcpPublishDisconnectsDisabledAndRemovedServers() async throws {
        let sess = Session()
        let log = McpConnectLog()
        sess.services.ensureMcpConnected = { log.ensure() }
        sess.services.reconnectMcp = { log.reconnect() }
        sess.services.disconnectMcp = { names in log.disconnect(names) }
        sess.state.sessionConfiguration.originalConfig.mcpServers = [
            "keep": ConfiguredMcpServer(url: "https://keep.example/mcp", enabled: true),
            "old": ConfiguredMcpServer(url: "https://old.example/mcp", enabled: true),
            "off": ConfiguredMcpServer(url: "https://off.example/mcp", enabled: false),
        ]
        let turn = sess.newTurnContext()
        sess.markMcpRuntimeDirty()
        let first = try await sess.captureStepContext(
            turn, cancellationToken: CancellationToken())
        let keepConnection = try XCTUnwrap(first.mcp?.connections["keep"])
        XCTAssertNotNil(first.mcp?.connections["old"])
        XCTAssertNil(first.mcp?.connections["off"])
        XCTAssertEqual(log.ensured, 1)
        XCTAssertEqual(log.disconnected, [])

        sess.state.sessionConfiguration.originalConfig.mcpServers["old"] = ConfiguredMcpServer(
            url: "https://old.example/mcp",
            enabled: false
        )
        sess.markMcpRuntimeDirty()
        let disabled = try await sess.captureStepContext(
            turn, cancellationToken: CancellationToken())
        XCTAssertTrue(disabled.mcp?.connections["keep"] === keepConnection)
        XCTAssertNil(disabled.mcp?.connections["old"])
        XCTAssertEqual(log.ensured, 1)
        XCTAssertEqual(log.reconnected, 0)
        XCTAssertEqual(log.disconnected, ["old"])

        sess.state.sessionConfiguration.originalConfig.mcpServers.removeValue(forKey: "keep")
        _ = try await sess.submit(.refreshMcpServers)
        try await waitUntil {
            sess.services.mcpRuntime.reconnectedPublishCount >= 1
                && sess.services.mcpRuntime.currentBinding?.connections["keep"] == nil
        }
        XCTAssertEqual(log.reconnected, 1)
        XCTAssertEqual(log.ensured, 1)
        XCTAssertEqual(log.disconnected, ["old", "keep"])
        XCTAssertEqual(log.trace, ["ensure", "disconnect:old", "reconnect", "disconnect:keep"])
        XCTAssertNil(sess.services.mcpRuntime.currentBinding?.connections["off"])
        XCTAssertNil(sess.activeTurn)
    }

    func testRefreshMcpServersLeavesTheRunningTurnAlone() async throws {
        let sess = Session()
        let entered = expectation(description: "sampling")
        let gate = SubmissionAck()
        defer { gate.signal() }
        sess.runSamplingOverride = { _, _ in
            entered.fulfill()
            await gate.wait()
            return SamplingRequestResult(needsFollowUp: false, lastAgentMessage: "kept")
        }
        _ = try await sess.submit(
            .userInput(TurnInputBuilder.user([.text(text: "hello", textElements: [])]))
        )
        await fulfillment(of: [entered], timeout: 1)
        let turnId = try XCTUnwrap(sess.activeTurn?.task?.turnContext.subId)
        let startedTurns = sess.emittedEvents.filter { event in
            if case .turnStarted = event { return true }
            return false
        }.count
        _ = try await sess.submit(.refreshMcpServers)
        try await waitUntil {
            sess.services.mcpRuntime.reconnectedPublishCount >= 1
                && !sess.services.mcpRuntime.reconnectPending
        }
        XCTAssertEqual(sess.activeTurn?.task?.turnContext.subId, turnId)
        XCTAssertFalse(sess.services.mcpRuntime.reconnectPending)
        XCTAssertEqual(sess.services.mcpRuntime.resourceCacheGeneration, 1)
        XCTAssertEqual(sess.services.mcpRuntime.reconnectedPublishCount, 1)
        XCTAssertFalse(sess.emittedEvents.contains { event in
            if case .turnAborted = event { return true }
            return false
        })
        XCTAssertEqual(
            sess.emittedEvents.filter { event in
                if case .turnStarted = event { return true }
                return false
            }.count,
            startedTurns
        )
        gate.signal()
        await sess.waitUntilIdle()
        XCTAssertEqual(sess.lastTaskAgentMessage, "kept")
        XCTAssertEqual(sess.lastStartedTurnId, turnId)
    }

    func testReloadUserConfigKeepsThePreviousLayerWhenTheFileIsInvalid() async throws {
        let sess = Session()
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("sage-config-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        sess.state.sessionConfiguration.codexHome = home.path
        sess.state.sessionConfiguration.stepSettings.model = "session-model"
        sess.features.enable(.goals)
        let configURL = home.appendingPathComponent("config.toml")
        try """
        [apps.calendar]
        enabled = false
        destructive_enabled = false
        """.write(to: configURL, atomically: true, encoding: .utf8)

        _ = try await sess.submit(.reloadUserConfig)
        let loaded = sess.state.sessionConfiguration.userConfigLayer
        XCTAssertEqual(userConfig(loaded, "apps", "calendar", "enabled"), .bool(false))
        XCTAssertEqual(userConfig(loaded, "apps", "calendar", "destructive_enabled"), .bool(false))
        XCTAssertEqual(sess.skillsCacheGeneration, 1)
        XCTAssertEqual(sess.pluginsCacheGeneration, 1)
        try await waitUntil { sess.services.mcpRuntime.publishCount == 1 }
        XCTAssertFalse(sess.services.mcpRuntime.dirty)
        XCTAssertFalse(sess.mcpPrewarmRequested)
        XCTAssertFalse(sess.services.mcpRuntime.lastPublishReconnected)
        XCTAssertFalse(sess.services.mcpRuntime.reconnectPending)
        XCTAssertEqual(sess.services.mcpRuntime.resourceCacheGeneration, 0)
        XCTAssertEqual(sess.state.sessionConfiguration.stepSettings.model, "session-model")
        XCTAssertTrue(sess.features.enabled(.goals))
        XCTAssertNil(sess.activeTurn)

        try """
        [apps.calendar]
        enabled = true

        [shell_environment_policy]
        exclude = ["SECRET_*", 17]
        """.write(to: configURL, atomically: true, encoding: .utf8)
        _ = try await sess.submit(.reloadUserConfig)
        XCTAssertEqual(
            userConfig(sess.state.sessionConfiguration.userConfigLayer, "apps", "calendar", "enabled"),
            .bool(false)
        )
        XCTAssertEqual(sess.skillsCacheGeneration, 1)

        try "enabled = \n".write(to: configURL, atomically: true, encoding: .utf8)
        _ = try await sess.submit(.reloadUserConfig)
        XCTAssertEqual(sess.skillsCacheGeneration, 1)
        XCTAssertEqual(sess.state.sessionConfiguration.stepSettings.model, "session-model")

        try FileManager.default.removeItem(at: configURL)
        try FileManager.default.createDirectory(at: configURL, withIntermediateDirectories: true)
        _ = try await sess.submit(.reloadUserConfig)
        XCTAssertEqual(sess.skillsCacheGeneration, 1)

        try FileManager.default.removeItem(at: configURL)
        _ = try await sess.submit(.reloadUserConfig)
        XCTAssertTrue(sess.state.sessionConfiguration.userConfigLayer.isEmpty)
        XCTAssertEqual(sess.skillsCacheGeneration, 2)
        XCTAssertEqual(sess.pluginsCacheGeneration, 2)
        XCTAssertTrue(sess.features.enabled(.goals))
        XCTAssertFalse(sess.emittedEvents.contains { event in
            if case .turnStarted = event { return true }
            return false
        })
    }

    func testReloadUserConfigOverlaysFilesAndSkipsAFailedBatch() async throws {
        let sess = Session()
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("sage-config-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let base = home.appendingPathComponent("base.toml")
        let profile = home.appendingPathComponent("profile.toml")
        try """
        model = "base"
        [apps.calendar]
        enabled = false
        """.write(to: base, atomically: true, encoding: .utf8)
        try "model = \"profile\"\n".write(to: profile, atomically: true, encoding: .utf8)
        sess.state.sessionConfiguration.userConfigPaths = [base.path, profile.path]
        sess.state.sessionConfiguration.stepSettings.model = "session-model"

        _ = try await sess.submit(.reloadUserConfig)
        let loaded = sess.state.sessionConfiguration.userConfigLayer
        XCTAssertEqual(userConfig(loaded, "model"), .string("profile"))
        XCTAssertEqual(userConfig(loaded, "apps", "calendar", "enabled"), .bool(false))
        XCTAssertEqual(sess.state.sessionConfiguration.stepSettings.model, "session-model")

        let broken = home.appendingPathComponent("broken.toml")
        try "model = \n".write(to: broken, atomically: true, encoding: .utf8)
        sess.state.sessionConfiguration.userConfigPaths = [base.path, broken.path]
        _ = try await sess.submit(.reloadUserConfig)
        XCTAssertEqual(
            userConfig(sess.state.sessionConfiguration.userConfigLayer, "model"),
            .string("profile")
        )
        XCTAssertEqual(sess.skillsCacheGeneration, 1)
    }

    func testReloadUserConfigLeavesTheRunningTurnAlone() async throws {
        let sess = Session()
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("sage-config-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        sess.state.sessionConfiguration.codexHome = home.path
        sess.features.enable(.goals)
        try "[apps.calendar]\nenabled = false\n".write(
            to: home.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
        let entered = expectation(description: "sampling")
        let gate = SubmissionAck()
        defer { gate.signal() }
        sess.runSamplingOverride = { _, _ in
            entered.fulfill()
            await gate.wait()
            return SamplingRequestResult(needsFollowUp: false, lastAgentMessage: "kept")
        }
        _ = try await sess.submit(
            .userInput(TurnInputBuilder.user([.text(text: "hello", textElements: [])]))
        )
        await fulfillment(of: [entered], timeout: 1)
        let turnId = try XCTUnwrap(sess.activeTurn?.task?.turnContext.subId)
        _ = try await sess.submit(.reloadUserConfig)
        XCTAssertEqual(sess.activeTurn?.task?.turnContext.subId, turnId)
        XCTAssertEqual(
            userConfig(sess.state.sessionConfiguration.userConfigLayer, "apps", "calendar", "enabled"),
            .bool(false)
        )
        XCTAssertTrue(sess.features.enabled(.goals))
        XCTAssertFalse(sess.emittedEvents.contains { event in
            if case .turnAborted = event { return true }
            return false
        })
        gate.signal()
        await sess.waitUntilIdle()
        XCTAssertEqual(sess.lastTaskAgentMessage, "kept")
        XCTAssertEqual(sess.lastStartedTurnId, turnId)
    }

    func testCleanBackgroundTerminalsStopsTrackedProcesses() async throws {
        let sess = Session()
        let first = try await trackSleepProcess(on: sess, processId: 11)
        let second = try await trackSleepProcess(on: sess, processId: 12)
        defer {
            first.terminate()
            second.terminate()
        }
        sess.services.unifiedExecManager.reserveProcessId(99)

        _ = try await sess.submit(.cleanBackgroundTerminals)
        XCTAssertEqual(sess.services.unifiedExecManager.processCount(), 0)
        XCTAssertTrue(sess.services.unifiedExecManager.reservedProcessIds().isEmpty)
        try await waitUntil { first.hasExited() && second.hasExited() }
        XCTAssertNil(sess.activeTurn)
        XCTAssertNil(sess.lastStartedTurnId)
        XCTAssertFalse(sess.emittedEvents.contains { event in
            if case .turnStarted = event { return true }
            return false
        })
    }

    func testCleanBackgroundTerminalsLeavesTheRunningTurnAlone() async throws {
        let sess = Session()
        let process = try await trackSleepProcess(on: sess, processId: 21)
        defer { process.terminate() }
        let entered = expectation(description: "sampling")
        let gate = SubmissionAck()
        defer { gate.signal() }
        sess.runSamplingOverride = { _, _ in
            entered.fulfill()
            await gate.wait()
            return SamplingRequestResult(needsFollowUp: false, lastAgentMessage: "kept")
        }
        _ = try await sess.submit(
            .userInput(TurnInputBuilder.user([.text(text: "hello", textElements: [])]))
        )
        await fulfillment(of: [entered], timeout: 1)
        let turnId = try XCTUnwrap(sess.activeTurn?.task?.turnContext.subId)
        _ = try await sess.submit(.cleanBackgroundTerminals)
        XCTAssertEqual(sess.services.unifiedExecManager.processCount(), 0)
        try await waitUntil { process.hasExited() }
        XCTAssertEqual(sess.activeTurn?.task?.turnContext.subId, turnId)
        XCTAssertFalse(sess.emittedEvents.contains { event in
            if case .turnAborted = event { return true }
            return false
        })
        gate.signal()
        await sess.waitUntilIdle()
        XCTAssertEqual(sess.lastTaskAgentMessage, "kept")
        XCTAssertEqual(sess.lastStartedTurnId, turnId)
    }

    func testReviewPromptRendersCommitAndBaseBranch() throws {
        let titled = try reviewPrompt(
            for: .commit(sha: "abcdef123456", title: "Fix parser"),
            mergeBase: nil
        )
        XCTAssertTrue(titled.contains("abcdef123456"))
        XCTAssertTrue(titled.contains("Fix parser"))
        XCTAssertEqual(
            userFacingReviewHint(.commit(sha: "abcdef123456", title: nil)),
            "commit abcdef1"
        )
        let backup = try reviewPrompt(for: .baseBranch(branch: "main"), mergeBase: nil)
        XCTAssertTrue(backup.contains("'main'"))
        XCTAssertTrue(backup.contains("merge-base"))
        let compared = try reviewPrompt(for: .baseBranch(branch: "main"), mergeBase: "abc123")
        XCTAssertTrue(compared.contains("abc123"))
        XCTAssertEqual(try reviewPrompt(for: .uncommittedChanges, mergeBase: nil), uncommittedReviewPrompt)
    }

    func testSubmitCompactEmitsContextCompacted() async throws {
        let sess = Session()
        _ = try await sess.submit(.compact)
        await sess.waitUntilIdle()
        XCTAssertTrue(sess.emittedEvents.contains { event in
            if case .contextCompacted = event { return true }
            return false
        })
    }

    func testNextEventReceivesTurnLifecycle() async throws {
        let sess = Session()
        sess.runSamplingOverride = { _, _ in
            SamplingRequestResult(needsFollowUp: false, lastAgentMessage: "done")
        }
        _ = try await sess.submit(
            .userInput(TurnInputBuilder.user([.text(text: "hello", textElements: [])]))
        )
        var sawStart = false
        var sawComplete = false
        for _ in 0..<12 {
            let event = try await sess.nextEvent()
            if case .turnStarted = event.msg { sawStart = true }
            if case .turnComplete = event.msg { sawComplete = true }
            if sawStart && sawComplete { break }
        }
        XCTAssertTrue(sawStart)
        XCTAssertTrue(sawComplete)
        await sess.waitUntilIdle()
    }

    func testShutdownCompletesAndClosesTheLoop() async throws {
        let sess = Session()
        await sess.shutdownAndWait()
        XCTAssertTrue(sess.state.shuttingDown)
        XCTAssertTrue(sess.emittedEvents.contains { event in
            if case .shutdownComplete = event { return true }
            return false
        })
        do {
            _ = try await sess.submit(.interrupt)
            XCTFail("submit after shutdown should fail")
        } catch let error as CodexErr {
            XCTAssertEqual(error.details, .internalAgentDied)
        }
    }

    func testCancelledTokenAbortsBeforeSampling() async {
        let sess = Session()
        let turn = TurnContext()
        var input: [SessionTurnInput] = [
            TurnInputBuilder.user([.text(text: "hello", textElements: [])]),
        ]
        var requirements = McpStartupRequirements()
        let token = CancellationToken()
        token.cancel()
        do {
            _ = try await runTurn(
                sess: sess,
                turnContext: turn,
                input: &input,
                mcpStartupRequirements: &requirements,
                prewarmedClientSession: nil,
                cancellationToken: token
            )
            XCTFail("expected turnAborted")
        } catch let error as CodexErr {
            XCTAssertEqual(error.details, .turnAborted)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testBuildToolCallFromFunctionAndCustom() throws {
        let function = ResponseItem.functionCall(
            id: nil,
            name: "echo",
            namespace: nil,
            arguments: "{\"q\":1}",
            encryptedFunctionArgs: nil,
            callId: "c1",
            internalChatMessageMetadataPassthrough: nil
        )
        let call = try XCTUnwrap(ToolRouter.buildToolCall(function))
        XCTAssertEqual(call.callId, "c1")
        XCTAssertEqual(call.toolName.name, "echo")
        XCTAssertEqual(call.toolName.namespace, DEFAULT_FUNCTION_NAMESPACE)
        if case .function(let arguments) = call.payload {
            XCTAssertEqual(arguments, "{\"q\":1}")
        } else {
            XCTFail("expected function payload")
        }

        let custom = ResponseItem.customToolCall(
            id: nil,
            status: nil,
            callId: "c2",
            name: "apply_patch",
            namespace: "functions",
            input: "***",
            internalChatMessageMetadataPassthrough: nil
        )
        let customCall = try XCTUnwrap(ToolRouter.buildToolCall(custom))
        XCTAssertEqual(customCall.callId, "c2")
        if case .custom(let input) = customCall.payload {
            XCTAssertEqual(input, "***")
        } else {
            XCTFail("expected custom payload")
        }

        let message = ResponseItem.message(
            id: nil,
            role: "assistant",
            content: [.outputText(text: "hi")],
            phase: nil,
            internalChatMessageMetadataPassthrough: nil
        )
        XCTAssertNil(try ToolRouter.buildToolCall(message))
    }

    func testHandleOutputItemDoneRecordsAssistantMessage() async throws {
        let sess = Session()
        let step = StepContext()
        let item = ResponseItem.message(
            id: nil,
            role: "assistant",
            content: [.outputText(text: "hello")],
            phase: nil,
            internalChatMessageMetadataPassthrough: nil
        )
        let output = try await handleOutputItemDone(
            sess: sess,
            stepContext: step,
            item: item,
            cancellationToken: CancellationToken()
        )
        XCTAssertEqual(output.lastAgentMessage, "hello")
        XCTAssertFalse(output.needsFollowUp)
        XCTAssertEqual(getLastAssistantMessageFromTurn(sess.cloneHistory().forPrompt()), "hello")
    }

    func testHandleOutputItemDoneDispatchesRegisteredTool() async throws {
        var registry = HarnessToolRegistry()
        registry.register(CurrentTimeHandler())
        let sess = Session()
        let step = StepContext(
            turn: TurnContext(),
            toolRouter: ToolRouter(
                registry: registry,
                modelVisibleSpecs: [],
                toolMode: .direct,
                canManageChildren: false
            )
        )
        let item = ResponseItem.functionCall(
            id: nil,
            name: CURRENT_TIME_TOOL_NAME,
            namespace: CLOCK_NAMESPACE,
            arguments: "{}",
            encryptedFunctionArgs: nil,
            callId: "t1",
            internalChatMessageMetadataPassthrough: nil
        )
        let output = try await handleOutputItemDone(
            sess: sess,
            stepContext: step,
            item: item,
            cancellationToken: CancellationToken()
        )
        XCTAssertTrue(output.needsFollowUp)
        let toolOutput = try await XCTUnwrap(output.toolFuture).value
        if case .functionCallOutput(_, let callId, _, _, let payload, _) = toolOutput {
            XCTAssertEqual(callId, "t1")
            XCTAssertTrue((payload.body.toText() ?? "").contains("UTC"))
        } else {
            XCTFail("expected function call output")
        }
    }

    func testTryRunSamplingRequestConsumesCompletedStream() async throws {
        let sess = Session()
        let step = StepContext()
        var client: ModelClientSession?
        sess.runSamplingStreamOverride = { _ in
            makeResponseStream([
                .success(.outputItemDone(.message(
                    id: nil,
                    role: "assistant",
                    content: [.outputText(text: "streamed")],
                    phase: nil,
                    internalChatMessageMetadataPassthrough: nil
                ))),
                .success(.completed(
                    responseId: "r1",
                    tokenUsage: nil,
                    usageMetadata: nil,
                    endTurn: true
                )),
            ])
        }
        let result = try await tryRunSamplingRequest(
            sess: sess,
            stepContext: step,
            clientSession: &client,
            prompt: Prompt(),
            cancellationToken: CancellationToken()
        )
        XCTAssertEqual(result.lastAgentMessage, "streamed")
        XCTAssertFalse(result.needsFollowUp)
    }

    func testTryRunSamplingRequestEmitsTurnDiffAfterCompleted() async throws {
        let sess = Session()
        let file = URL(fileURLWithPath: "/tmp/turn-diff.txt")
        sess.services.turnDiffTracker.trackDelta(
            "",
            AppliedPatchDelta(changes: [
                AppliedPatchChange(path: file, kind: .add(content: "hi\n", overwrittenContent: nil)),
            ])
        )
        let step = StepContext()
        var client: ModelClientSession?
        sess.runSamplingStreamOverride = { _ in
            makeResponseStream([
                .success(.completed(
                    responseId: "r1",
                    tokenUsage: nil,
                    usageMetadata: nil,
                    endTurn: true
                )),
            ])
        }
        _ = try await tryRunSamplingRequest(
            sess: sess,
            stepContext: step,
            clientSession: &client,
            prompt: Prompt(),
            cancellationToken: CancellationToken()
        )
        XCTAssertTrue(sess.emittedEvents.contains { event in
            if case .turnDiff(let payload) = event {
                return payload.unifiedDiff.contains("turn-diff.txt")
            }
            return false
        })
    }

    func testTryRunSamplingRequestThrowsWhenStreamEndsEarly() async {
        let sess = Session()
        let step = StepContext()
        var client: ModelClientSession?
        sess.runSamplingStreamOverride = { _ in
            makeResponseStream([
                .success(.outputItemDone(.message(
                    id: nil,
                    role: "assistant",
                    content: [.outputText(text: "partial")],
                    phase: nil,
                    internalChatMessageMetadataPassthrough: nil
                ))),
            ])
        }
        do {
            _ = try await tryRunSamplingRequest(
                sess: sess,
                stepContext: step,
                clientSession: &client,
                prompt: Prompt(),
                cancellationToken: CancellationToken()
            )
            XCTFail("expected stream error")
        } catch let error as CodexErr {
            if case .stream(let message) = error.details {
                XCTAssertTrue(message.contains("response.completed"))
            } else {
                XCTFail("unexpected \(error.details)")
            }
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testRunTurnUsesSamplingStreamOverride() async throws {
        let sess = Session()
        let turn = TurnContext()
        sess.runSamplingStreamOverride = { _ in
            makeResponseStream([
                .success(.outputItemDone(.message(
                    id: nil,
                    role: "assistant",
                    content: [.outputText(text: "from-stream")],
                    phase: nil,
                    internalChatMessageMetadataPassthrough: nil
                ))),
                .success(.completed(
                    responseId: "r2",
                    tokenUsage: nil,
                    usageMetadata: nil,
                    endTurn: true
                )),
            ])
        }
        var input: [SessionTurnInput] = [
            TurnInputBuilder.user([.text(text: "hi", textElements: [])]),
        ]
        var requirements = McpStartupRequirements()
        let message = try await runTurn(
            sess: sess,
            turnContext: turn,
            input: &input,
            mcpStartupRequirements: &requirements,
            prewarmedClientSession: nil,
            cancellationToken: CancellationToken()
        )
        XCTAssertEqual(message, "from-stream")
    }

    func testRequiredMcpServersIncludesPluginAndSkillDependencies() {
        let sess = Session()
        sess.services.availablePlugins = [
            PluginCapabilitySummary(
                configName: "weather",
                displayName: "Weather",
                hasSkills: true,
                mcpServerNames: ["weather-mcp"]
            ),
        ]
        sess.services.skillsLookup.insertHostSkill(
            name: "deploy",
            path: "/tmp/deploy/SKILL.md",
            prompt: "Deploy the service.",
            pluginId: "weather",
            mcpServers: ["deploy-mcp"]
        )
        let (servers, plugins) = requiredMcpServersForInput(
            sess: sess,
            turnContext: TurnContext(),
            userInput: [
                .mention(name: "weather", path: "plugin://weather"),
                .skill(name: "deploy", path: "/tmp/deploy/SKILL.md"),
                .mention(name: "linear", path: "mcp://linear/issues"),
            ]
        )
        XCTAssertEqual(Set(servers), ["weather-mcp", "deploy-mcp", "linear"])
        XCTAssertEqual(plugins.map(\.configName), ["weather"])
    }

    func testBuildSkillsAndPluginsInjectsSkillAndPluginItems() async throws {
        let sess = Session()
        sess.services.availablePlugins = [
            PluginCapabilitySummary(
                configName: "weather",
                displayName: "Weather",
                hasSkills: true,
                mcpServerNames: ["weather-mcp"]
            ),
        ]
        sess.services.skillsLookup.insertHostSkill(
            name: "deploy",
            path: "/tmp/deploy/SKILL.md",
            prompt: "Deploy the service."
        )
        let step = StepContext()
        let built = await buildSkillsAndPlugins(
            sess: sess,
            stepContext: step,
            userInput: [
                .mention(name: "weather", path: "plugin://weather"),
                .skill(name: "deploy", path: "/tmp/deploy/SKILL.md"),
            ],
            mentionedPlugins: sess.services.availablePlugins,
            cancellationToken: CancellationToken()
        )
        let items = try XCTUnwrap(built?.0)
        XCTAssertTrue(items.contains { item in
            if case .message(_, _, let content, _, _) = item {
                return content.contains { part in
                    if case .inputText(let text) = part {
                        return text.contains("<skill>") && text.contains("Deploy the service.")
                    }
                    return false
                }
            }
            return false
        })
        XCTAssertTrue(items.contains { item in
            if case .message(_, _, let content, _, _) = item {
                return content.contains { part in
                    if case .inputText(let text) = part {
                        return text.contains("`Weather` plugin")
                    }
                    return false
                }
            }
            return false
        })
    }

    func testBuildSkillsAndPluginsSkipsGuardianSource() async {
        let sess = Session()
        sess.services.availablePlugins = [
            PluginCapabilitySummary(configName: "weather", displayName: "Weather", hasSkills: true),
        ]
        let step = StepContext(turn: TurnContext(sessionSource: .internal(.guardian)))
        let built = await buildSkillsAndPlugins(
            sess: sess,
            stepContext: step,
            userInput: [.mention(name: "weather", path: "plugin://weather")],
            mentionedPlugins: sess.services.availablePlugins,
            cancellationToken: CancellationToken()
        )
        XCTAssertEqual(built?.0.count, 0)
        XCTAssertEqual(built?.1, [])
    }

    func testGuardianCheckPendingRejectsOversizedReview() {
        let sess = Session()
        sess.pendingReviewContext = PendingReviewContext(estimatedTokens: 10_000, userInputs: [
            .text(text: "review", textElements: []),
        ])
        var config = Config()
        config.modelContextWindow = 100
        let turn = TurnContext(modelContextWindow: 100, config: config)
        XCTAssertThrowsError(try checkPendingGuardianInput(sess: sess, turnContext: turn)) { error in
            guard let err = error as? CodexErr else {
                return XCTFail("expected CodexErr")
            }
            XCTAssertEqual(err.details, .contextWindowExceeded)
            XCTAssertEqual(sess.exhaustedReviewBudget, .detected)
        }
    }

    func testGuardianFinalizeReplacesUserInput() throws {
        let sess = Session()
        sess.pendingReviewContext = PendingReviewContext(text: "final review evidence")
        var input: [SessionTurnInput] = [
            TurnInputBuilder.user([.text(text: "placeholder", textElements: [])]),
        ]
        try finalizeGuardianInput(sess: sess, stepContext: StepContext(), input: &input)
        XCTAssertNil(sess.pendingReviewContext)
        XCTAssertNil(sess.exhaustedReviewBudget)
        guard case .userInput(let content, _, _) = input[0] else {
            return XCTFail("expected user input")
        }
        XCTAssertEqual(content, [.text(text: "final review evidence", textElements: [])])
    }

    func testGuardianCheckPromptRejectsOversizedAssembledPrompt() {
        let sess = Session()
        var config = Config()
        config.modelContextWindow = 100
        let prompt = Prompt(
            input: [
                .message(
                    id: nil,
                    role: "user",
                    content: [.inputText(text: String(repeating: "word ", count: 2_000))],
                    phase: nil,
                    internalChatMessageMetadataPassthrough: nil
                ),
            ]
        )
        XCTAssertThrowsError(
            try GuardianRequestBudget.checkPrompt(
                session: sess,
                prompt: prompt,
                config: config,
                model: minimalModelInfo()
            )
        ) { error in
            guard let err = error as? CodexErr else {
                return XCTFail("expected CodexErr")
            }
            XCTAssertEqual(err.details, .contextWindowExceeded)
            XCTAssertEqual(sess.exhaustedReviewBudget, .detected)
        }
    }

    func testTryRunSamplingRequestEmitsAssistantTextDeltas() async throws {
        let sess = Session()
        let step = StepContext()
        var client: ModelClientSession?
        sess.runSamplingStreamOverride = { _ in
            makeResponseStream([
                .success(.outputTextDelta("Hel")),
                .success(.outputTextDelta("lo")),
                .success(.outputItemDone(.message(
                    id: nil,
                    role: "assistant",
                    content: [.outputText(text: "Hello")],
                    phase: nil,
                    internalChatMessageMetadataPassthrough: nil
                ))),
                .success(.completed(
                    responseId: "r3",
                    tokenUsage: nil,
                    usageMetadata: nil,
                    endTurn: true
                )),
            ])
        }
        let result = try await tryRunSamplingRequest(
            sess: sess,
            stepContext: step,
            clientSession: &client,
            prompt: Prompt(),
            cancellationToken: CancellationToken()
        )
        XCTAssertEqual(result.lastAgentMessage, "Hello")
        let deltas = sess.emittedEvents.compactMap { event -> String? in
            if case .agentMessageContentDelta(let delta) = event { return delta.delta }
            return nil
        }
        XCTAssertEqual(deltas.joined(), "Hello")
    }

    func testTryRunSamplingRequestPlanModeParsesProposedPlan() async throws {
        let sess = Session()
        let turn = TurnContext(
            collaborationMode: CollaborationMode(
                mode: .plan,
                settings: Settings(model: "gpt-5")
            )
        )
        let step = StepContext(turn: turn)
        var client: ModelClientSession?
        let streamed = "intro\n<proposed_plan>\nstep one\n</proposed_plan>\n"
        sess.runSamplingStreamOverride = { _ in
            makeResponseStream([
                .success(.outputTextDelta(streamed)),
                .success(.outputItemDone(.message(
                    id: nil,
                    role: "assistant",
                    content: [.outputText(text: streamed)],
                    phase: nil,
                    internalChatMessageMetadataPassthrough: nil
                ))),
                .success(.completed(
                    responseId: "r4",
                    tokenUsage: nil,
                    usageMetadata: nil,
                    endTurn: true
                )),
            ])
        }
        _ = try await tryRunSamplingRequest(
            sess: sess,
            stepContext: step,
            clientSession: &client,
            prompt: Prompt(),
            cancellationToken: CancellationToken()
        )
        XCTAssertTrue(sess.emittedEvents.contains { event in
            if case .itemStarted(let started) = event, case .plan = started.item {
                return true
            }
            return false
        })
        XCTAssertTrue(sess.emittedEvents.contains { event in
            if case .itemCompleted(let completed) = event,
               case .plan(let plan) = completed.item {
                return plan.text.contains("step one")
            }
            return false
        })
        XCTAssertTrue(sess.emittedEvents.contains { event in
            if case .agentMessageContentDelta(let delta) = event {
                return delta.delta.contains("intro")
            }
            return false
        })
    }

    func testRunAutoCompactReplacesHistoryWithSummary() async throws {
        let sess = Session()
        sess.state.recordItems([
            .message(
                id: nil,
                role: "user",
                content: [.inputText(text: "keep me")],
                phase: nil,
                internalChatMessageMetadataPassthrough: nil
            ),
            .message(
                id: nil,
                role: "assistant",
                content: [.outputText(text: "long tool chatter")],
                phase: nil,
                internalChatMessageMetadataPassthrough: nil
            ),
        ])
        sess.runCompactOverride = { _ in "folded work" }
        var client: ModelClientSession?
        try await runAutoCompact(
            sess: sess,
            stepContext: StepContext(),
            clientSession: &client,
            injection: .doNotInject
        )
        let prompt = sess.cloneHistory().forPrompt()
        XCTAssertEqual(prompt.count, 2)
        XCTAssertEqual(contentItemsToText(messageContent(prompt[0])), "keep me")
        XCTAssertEqual(prompt[1], wrapCompactionSummary("folded work"))
        XCTAssertEqual(sess.lastRemoteCompact?.summary, "folded work")
        XCTAssertEqual(sess.lastRemoteCompact?.succeeded, true)
        XCTAssertTrue(sess.emittedEvents.contains { event in
            if case .contextCompacted = event { return true }
            return false
        })
    }

    func testRunAutoCompactPreCompactHookAborts() async {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("sage-compact-hook-\(UUID().uuidString)", isDirectory: true)
        let hooks = temp.appendingPathComponent(".sage", isDirectory: true)
        try? FileManager.default.createDirectory(at: hooks, withIntermediateDirectories: true)
        try? """
        { "pre_compact": [{ "action": "deny", "reason": "no fold" }] }
        """.write(to: hooks.appendingPathComponent("hooks.json"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: temp) }

        let sess = Session()
        var client: ModelClientSession?
        do {
            try await runAutoCompact(
                sess: sess,
                stepContext: StepContext(turn: TurnContext(cwd: temp.path)),
                clientSession: &client,
                injection: .doNotInject
            )
            XCTFail("expected turnAborted")
        } catch let error as CodexErr {
            XCTAssertEqual(error.details, .turnAborted)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testRunAutoCompactScriptSeesAutoTrigger() async throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("sage-compact-source-\(UUID().uuidString)", isDirectory: true)
        let hooks = temp.appendingPathComponent(".sage", isDirectory: true)
        try FileManager.default.createDirectory(at: hooks, withIntermediateDirectories: true)
        try #"""
        {
          "pre_compact": [{ "run": "python3 -c \"import json,sys; d=json.load(sys.stdin); open('pre.txt','w').write(d.get('trigger','')+'|'+d.get('hook_event_name',''))\"" }],
          "post_compact": [{ "run": "python3 -c \"import json,sys; d=json.load(sys.stdin); open('post.txt','w').write(d.get('trigger','')+'|'+d.get('hook_event_name',''))\"" }]
        }
        """#.write(to: hooks.appendingPathComponent("hooks.json"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: temp) }

        let sess = Session()
        var client: ModelClientSession?
        try await runAutoCompact(
            sess: sess,
            stepContext: StepContext(turn: TurnContext(cwd: temp.path)),
            clientSession: &client,
            injection: .doNotInject
        )
        XCTAssertEqual(
            try String(contentsOf: temp.appendingPathComponent("pre.txt"), encoding: .utf8),
            "auto|PreCompact"
        )
        XCTAssertEqual(
            try String(contentsOf: temp.appendingPathComponent("post.txt"), encoding: .utf8),
            "auto|PostCompact"
        )
    }

    func testRunTurnStopHookSamplesOnceMore() async throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("sage-stop-source-\(UUID().uuidString)", isDirectory: true)
        let hooks = temp.appendingPathComponent(".sage", isDirectory: true)
        try FileManager.default.createDirectory(at: hooks, withIntermediateDirectories: true)
        try #"""
        {
          "stop": [
            { "action": "continue", "reason": "one more look" },
            { "run": "python3 -c \"import json,sys; d=json.load(sys.stdin); open('stop.txt','a').write(d.get('hook_event_name','')+'|'+str(d.get('stop_hook_active')).lower()+'|'+str(d.get('last_assistant_message') or '')+'\\n')\"" }
          ]
        }
        """#.write(to: hooks.appendingPathComponent("hooks.json"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: temp) }

        let sess = Session()
        var samples = 0
        sess.runSamplingOverride = { _, _ in
            samples += 1
            return SamplingRequestResult(needsFollowUp: false, lastAgentMessage: "done-\(samples)")
        }
        var input: [SessionTurnInput] = [
            TurnInputBuilder.user([.text(text: "hello", textElements: [])]),
        ]
        var requirements = McpStartupRequirements()
        let message = try await runTurn(
            sess: sess,
            turnContext: TurnContext(cwd: temp.path),
            input: &input,
            mcpStartupRequirements: &requirements,
            prewarmedClientSession: nil,
            cancellationToken: CancellationToken()
        )
        XCTAssertEqual(samples, 2)
        XCTAssertEqual(message, "done-2")
        XCTAssertTrue(sess.stopHookActive)
        XCTAssertEqual(
            try String(contentsOf: temp.appendingPathComponent("stop.txt"), encoding: .utf8),
            "Stop|false|done-1\n"
        )
    }

    func testRunTurnAfterAgentSeesUserAndLastAssistant() async throws {
        let probe = AfterAgentProbe()
        let sess = Session()
        sess.services.afterAgentHooks = [
            Hook(name: "probe") { payload in
                if case .afterAgent(let event) = payload.hookEvent {
                    probe.record(event)
                }
                return .success
            },
        ]
        sess.runSamplingOverride = { _, _ in
            SamplingRequestResult(needsFollowUp: false, lastAgentMessage: "done")
        }
        var input: [SessionTurnInput] = [
            TurnInputBuilder.user([.text(text: "hello", textElements: [])]),
        ]
        var requirements = McpStartupRequirements()
        let message = try await runTurn(
            sess: sess,
            turnContext: TurnContext(),
            input: &input,
            mcpStartupRequirements: &requirements,
            prewarmedClientSession: nil,
            cancellationToken: CancellationToken()
        )
        XCTAssertEqual(message, "done")
        XCTAssertEqual(probe.callCount, 1)
        XCTAssertEqual(probe.lastAssistant, "done")
        XCTAssertTrue(probe.inputMessages.contains("hello"))
    }

    func testRunTurnAfterAgentAbortReturnsNilAndEmitsError() async throws {
        let sess = Session()
        sess.services.afterAgentHooks = [
            Hook(name: "boom") { _ in
                .failedAbort(CodexErr.fatal("nope"))
            },
        ]
        sess.runSamplingOverride = { _, _ in
            SamplingRequestResult(needsFollowUp: false, lastAgentMessage: "done")
        }
        var input: [SessionTurnInput] = [
            TurnInputBuilder.user([.text(text: "hello", textElements: [])]),
        ]
        var requirements = McpStartupRequirements()
        let message = try await runTurn(
            sess: sess,
            turnContext: TurnContext(),
            input: &input,
            mcpStartupRequirements: &requirements,
            prewarmedClientSession: nil,
            cancellationToken: CancellationToken()
        )
        XCTAssertNil(message)
        XCTAssertTrue(sess.emittedEvents.contains { event in
            if case .error(let error) = event {
                return error.message.contains("after_agent hook 'boom'")
                    && error.message.contains("aborted turn completion")
            }
            return false
        })
    }

    func testRunTurnAfterAgentWaitsUntilStopContinuationFinishes() async throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("sage-after-agent-stop-\(UUID().uuidString)", isDirectory: true)
        let hooks = temp.appendingPathComponent(".sage", isDirectory: true)
        try FileManager.default.createDirectory(at: hooks, withIntermediateDirectories: true)
        try #"""
        {
          "stop": [{ "action": "continue", "reason": "one more look" }]
        }
        """#.write(to: hooks.appendingPathComponent("hooks.json"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: temp) }

        let probe = AfterAgentProbe()
        let sess = Session()
        sess.services.afterAgentHooks = [
            Hook(name: "probe") { payload in
                if case .afterAgent(let event) = payload.hookEvent {
                    probe.record(event)
                }
                return .success
            },
        ]
        var samples = 0
        sess.runSamplingOverride = { _, _ in
            samples += 1
            return SamplingRequestResult(needsFollowUp: false, lastAgentMessage: "done-\(samples)")
        }
        var input: [SessionTurnInput] = [
            TurnInputBuilder.user([.text(text: "hello", textElements: [])]),
        ]
        var requirements = McpStartupRequirements()
        let message = try await runTurn(
            sess: sess,
            turnContext: TurnContext(cwd: temp.path),
            input: &input,
            mcpStartupRequirements: &requirements,
            prewarmedClientSession: nil,
            cancellationToken: CancellationToken()
        )
        XCTAssertEqual(samples, 2)
        XCTAssertEqual(message, "done-2")
        XCTAssertEqual(probe.callCount, 1)
        XCTAssertEqual(probe.lastAssistant, "done-2")
    }

    func testApproveGuardianDeniedActionInjectsTheApprovedAction() async throws {
        let sess = Session()
        _ = try await sess.submit(.approveGuardianDeniedAction(deniedGuardianAssessment()))
        XCTAssertNil(sess.lastStartedTurnId)
        XCTAssertNil(sess.activeTurn)
        XCTAssertFalse(sess.emittedEvents.contains { event in
            if case .turnStarted = event { return true }
            return false
        })
        guard case .message(_, let role, let content, _, let passthrough) =
            sess.cloneHistory().forPrompt().last,
            case .inputText(let text) = content.first
        else {
            return XCTFail("expected approved action")
        }
        XCTAssertEqual(role, "developer")
        XCTAssertEqual(
            passthrough?.contentItemKinds,
            [ContentItemKind("guardian.approved_action")]
        )
        XCTAssertEqual(text, expectedApprovedGuardianActionText())
    }

    func testApproveGuardianDeniedActionQueuesOnTheActiveTurn() async throws {
        let sess = Session()
        sess.activeTurn = ActiveTurn(
            task: RunningTask(kind: .regular, turnContext: TurnContext(subId: "turn-1"))
        )
        _ = try await sess.submit(.approveGuardianDeniedAction(deniedGuardianAssessment()))
        XCTAssertTrue(sess.cloneHistory().forPrompt().isEmpty)
        XCTAssertNil(sess.lastStartedTurnId)
        guard case .responseItem(let item) = sess.activeTurn?.turnState.pendingInput.items.first,
              case .message(_, let role, let content, _, _) = item,
              case .inputText(let text) = content.first
        else {
            return XCTFail("expected queued approved action")
        }
        XCTAssertEqual(role, "developer")
        XCTAssertEqual(text, expectedApprovedGuardianActionText())
    }

    func testApproveGuardianDeniedActionIgnoresOtherStatuses() async throws {
        let sess = Session()
        _ = try await sess.submit(
            .approveGuardianDeniedAction(deniedGuardianAssessment(status: .approved))
        )
        XCTAssertTrue(sess.cloneHistory().forPrompt().isEmpty)
        XCTAssertNil(sess.activeTurn)
        XCTAssertNil(sess.lastStartedTurnId)
    }

    func testInjectHookContextIfRunningRequiresLiveTask() {
        let sess = Session()
        let item = HookAdditionalContext(text: "hint").asResponseItem()
        XCTAssertEqual(sess.injectHookContextIfRunning([item])?.count, 1)
        sess.activeTurn = ActiveTurn(turnState: TurnState())
        XCTAssertEqual(sess.injectHookContextIfRunning([item])?.count, 1)
        sess.activeTurn = ActiveTurn(
            task: RunningTask(kind: .regular, turnContext: TurnContext()),
            turnState: TurnState()
        )
        XCTAssertNil(sess.injectHookContextIfRunning([item]))
        XCTAssertEqual(sess.activeTurn?.turnState.pendingInput.items.count, 1)
        XCTAssertNil(sess.injectIfRunning([item]))
        XCTAssertEqual(sess.activeTurn?.turnState.pendingInput.items.count, 2)
    }

    func testRecordAdditionalContextsUsesHookFragment() {
        let sess = Session()
        recordAdditionalContexts(
            sess: sess,
            turnContext: TurnContext(),
            contexts: ["remember this"]
        )
        guard case .message(_, let role, let content, _, let passthrough) =
            sess.cloneHistory().forPrompt().last
        else {
            return XCTFail("expected hook context message")
        }
        XCTAssertEqual(role, "user")
        XCTAssertEqual(content, [.inputText(text: "remember this")])
        XCTAssertEqual(passthrough?.contentItemKinds, [ContentItemKind("hooks.additional_context")])
    }

    func testDrainAfterSamplingInjectsPendingHookContext() {
        let sess = Session()
        let turn = TurnContext()
        sess.activeTurn = ActiveTurn(
            task: RunningTask(kind: .regular, turnContext: turn),
            turnState: TurnState()
        )
        sess.enqueuePendingHookContexts(["from async hook"])
        drainAsyncHookResults(sess: sess, turnContext: turn, beforeUserPrompt: false)
        XCTAssertTrue(sess.cloneHistory().forPrompt().isEmpty)
        XCTAssertEqual(sess.activeTurn?.turnState.pendingInput.items.count, 1)
        guard case .responseItem(let item) = sess.activeTurn?.turnState.pendingInput.items.first,
              case .message(_, _, let content, _, let passthrough) = item
        else {
            return XCTFail("expected pending hook response item")
        }
        XCTAssertEqual(content, [.inputText(text: "from async hook")])
        XCTAssertEqual(passthrough?.contentItemKinds, [ContentItemKind("hooks.additional_context")])
    }

    func testDrainBeforePromptRecordsPendingHookContext() {
        let sess = Session()
        sess.enqueuePendingHookContexts(["before prompt"])
        drainAsyncHookResults(sess: sess, turnContext: TurnContext(), beforeUserPrompt: true)
        XCTAssertEqual(sessionStartContextCount(sess, "before prompt"), 1)
    }

    func testSubmitInterruptScriptSeesInterruptEvent() async throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("sage-interrupt-source-\(UUID().uuidString)", isDirectory: true)
        let hooks = temp.appendingPathComponent(".sage", isDirectory: true)
        try FileManager.default.createDirectory(at: hooks, withIntermediateDirectories: true)
        try #"""
        {
          "interrupt": [{ "run": "python3 -c \"import json,sys; d=json.load(sys.stdin); open('interrupt.txt','w').write(d.get('hook_event_name','')+'|'+d.get('turn_id',''))\"" }]
        }
        """#.write(to: hooks.appendingPathComponent("hooks.json"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: temp) }

        let sess = Session()
        sess.services.hookProjectRoot = temp
        let token = CancellationToken()
        let turn = TurnContext(cwd: temp.path)
        let entered = expectation(description: "sampling")
        sess.runSamplingOverride = { _, _ in
            entered.fulfill()
            while !token.isCancelled {
                try await Task.sleep(for: .milliseconds(10))
            }
            throw CodexErr(details: .turnAborted)
        }
        let running = Task {
            await sess.spawnTask(
                RegularSessionTask(),
                turnContext: turn,
                input: [TurnInputBuilder.user([.text(text: "hello", textElements: [])])],
                cancellationToken: token
            )
        }
        await fulfillment(of: [entered], timeout: 1)
        _ = try await sess.submit(.interrupt)
        await running.value
        XCTAssertEqual(sess.lastTurnAbortReason, .interrupted)
        XCTAssertEqual(
            try String(contentsOf: temp.appendingPathComponent("interrupt.txt"), encoding: .utf8),
            "Interrupt|\(turn.subId)"
        )
    }

    func testShutdownScriptSeesSessionEndReason() async throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("sage-session-end-\(UUID().uuidString)", isDirectory: true)
        let hooks = temp.appendingPathComponent(".sage", isDirectory: true)
        try FileManager.default.createDirectory(at: hooks, withIntermediateDirectories: true)
        try #"""
        {
          "session_end": [{ "run": "python3 -c \"import json,sys; d=json.load(sys.stdin); open('end.txt','w').write(d.get('hook_event_name','')+'|'+d.get('reason',''))\"" }]
        }
        """#.write(to: hooks.appendingPathComponent("hooks.json"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: temp) }

        let sess = Session()
        sess.services.hookProjectRoot = temp
        await sess.shutdownAndWait()
        XCTAssertEqual(
            try String(contentsOf: temp.appendingPathComponent("end.txt"), encoding: .utf8),
            "SessionEnd|other"
        )
    }

    func testTryRunSamplingRequestRecordsUsageAndReasoningDelta() async throws {
        let sess = Session()
        let step = StepContext()
        var client: ModelClientSession?
        sess.runSamplingStreamOverride = { _ in
            makeResponseStream([
                .success(.reasoningContentDelta(delta: "think", contentIndex: 0)),
                .success(.outputItemDone(.message(
                    id: nil,
                    role: "assistant",
                    content: [.outputText(text: "done")],
                    phase: nil,
                    internalChatMessageMetadataPassthrough: nil
                ))),
                .success(.completed(
                    responseId: "r5",
                    tokenUsage: TokenUsage(inputTokens: 10, outputTokens: 4, totalTokens: 14),
                    usageMetadata: nil,
                    endTurn: false
                )),
            ])
        }
        let result = try await tryRunSamplingRequest(
            sess: sess,
            stepContext: step,
            clientSession: &client,
            prompt: Prompt(),
            cancellationToken: CancellationToken()
        )
        XCTAssertTrue(result.needsFollowUp)
        XCTAssertEqual(sess.getTotalTokenUsage(), 14)
        XCTAssertTrue(sess.emittedEvents.contains { event in
            if case .reasoningContentDelta(let delta) = event {
                return delta.delta == "think"
            }
            return false
        })
    }

    func testSessionStartHookCanStopTurn() async {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("sage-session-start-\(UUID().uuidString)", isDirectory: true)
        let hooks = temp.appendingPathComponent(".sage", isDirectory: true)
        try? FileManager.default.createDirectory(at: hooks, withIntermediateDirectories: true)
        try? """
        { "session_start": [{ "action": "deny", "reason": "blocked start" }] }
        """.write(to: hooks.appendingPathComponent("hooks.json"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: temp) }

        let sess = Session()
        let turn = TurnContext(cwd: temp.path)
        let stopped = await runPendingSessionStartHooks(sess: sess, turnContext: turn)
        XCTAssertTrue(stopped)
        XCTAssertTrue(sess.sessionStartHooksConsumed)
        XCTAssertTrue(sess.emittedEvents.contains { event in
            if case .error(let error) = event {
                return error.message == "blocked start"
            }
            return false
        })
        let again = await runPendingSessionStartHooks(sess: sess, turnContext: turn)
        XCTAssertFalse(again)
    }

    func testSessionStartContinueInjectsContextIntoHistory() async {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("sage-session-start-ctx-\(UUID().uuidString)", isDirectory: true)
        let hooks = temp.appendingPathComponent(".sage", isDirectory: true)
        try? FileManager.default.createDirectory(at: hooks, withIntermediateDirectories: true)
        try? """
        { "session_start": [{ "action": "continue", "reason": "remember the work plan" }] }
        """.write(to: hooks.appendingPathComponent("hooks.json"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: temp) }

        let sess = Session()
        let turn = TurnContext(cwd: temp.path)
        let stopped = await runPendingSessionStartHooks(sess: sess, turnContext: turn)
        XCTAssertFalse(stopped)
        XCTAssertEqual(sessionStartContextCount(sess, "remember the work plan"), 1)
        let again = await runPendingSessionStartHooks(sess: sess, turnContext: turn)
        XCTAssertFalse(again)
        XCTAssertEqual(sessionStartContextCount(sess, "remember the work plan"), 1)
    }

    func testSessionStartRunsAgainAfterCompact() async {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("sage-session-start-compact-\(UUID().uuidString)", isDirectory: true)
        let hooks = temp.appendingPathComponent(".sage", isDirectory: true)
        try? FileManager.default.createDirectory(at: hooks, withIntermediateDirectories: true)
        try? """
        { "session_start": [{ "action": "continue", "reason": "after compact" }] }
        """.write(to: hooks.appendingPathComponent("hooks.json"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: temp) }

        let sess = Session()
        let turn = TurnContext(cwd: temp.path)
        let first = await runPendingSessionStartHooks(sess: sess, turnContext: turn)
        XCTAssertFalse(first)
        XCTAssertEqual(sessionStartContextCount(sess, "after compact"), 1)
        sess.replaceCompactedHistory([])
        XCTAssertEqual(sessionStartContextCount(sess, "after compact"), 0)
        let afterCompact = await runPendingSessionStartHooks(sess: sess, turnContext: turn)
        XCTAssertFalse(afterCompact)
        XCTAssertEqual(sessionStartContextCount(sess, "after compact"), 1)
    }

    func testSessionStartScriptSeesCompactSourceAfterHistoryReplace() async {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("sage-session-start-source-\(UUID().uuidString)", isDirectory: true)
        let hooks = temp.appendingPathComponent(".sage", isDirectory: true)
        try? FileManager.default.createDirectory(at: hooks, withIntermediateDirectories: true)
        try? #"""
        { "session_start": [{ "run": "python3 -c \"import json,sys; d=json.load(sys.stdin); open('source.txt','a').write(d.get('source','')+'\\n')\"" }] }
        """#.write(to: hooks.appendingPathComponent("hooks.json"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: temp) }

        let sess = Session()
        let turn = TurnContext(cwd: temp.path)
        let first = await runPendingSessionStartHooks(sess: sess, turnContext: turn)
        XCTAssertFalse(first)
        sess.replaceCompactedHistory([])
        let afterCompact = await runPendingSessionStartHooks(sess: sess, turnContext: turn)
        XCTAssertFalse(afterCompact)
        let written = (try? String(
            contentsOf: temp.appendingPathComponent("source.txt"),
            encoding: .utf8
        )) ?? ""
        XCTAssertEqual(
            written.split(whereSeparator: \.isNewline).map(String.init),
            ["startup", "compact"]
        )
    }

    func testAttachStartSourcePrefersPendingClearAndFork() {
        XCTAssertEqual(
            ExecuteHarnessAttach.attachStartSource(pending: .clear, historyEmpty: true),
            .clear
        )
        XCTAssertEqual(
            ExecuteHarnessAttach.attachStartSource(pending: .fork, historyEmpty: true),
            .fork
        )
        XCTAssertEqual(
            ExecuteHarnessAttach.attachStartSource(pending: nil, historyEmpty: true),
            .startup
        )
        XCTAssertEqual(
            ExecuteHarnessAttach.attachStartSource(pending: nil, historyEmpty: false),
            .resume
        )
        XCTAssertEqual(
            ExecuteHarnessAttach.makeSession(history: [], startSource: .clear)
                .takePendingSessionStartSource(),
            .clear
        )
    }

    func testSessionStartScriptSeesClearSourceAfterHistoryReset() async {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("sage-session-start-clear-\(UUID().uuidString)", isDirectory: true)
        let hooks = temp.appendingPathComponent(".sage", isDirectory: true)
        try? FileManager.default.createDirectory(at: hooks, withIntermediateDirectories: true)
        try? #"""
        { "session_start": [{ "run": "python3 -c \"import json,sys; d=json.load(sys.stdin); open('source.txt','a').write(d.get('source','')+'\\n')\"" }] }
        """#.write(to: hooks.appendingPathComponent("hooks.json"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: temp) }

        let sess = Session()
        let turn = TurnContext(cwd: temp.path)
        let first = await runPendingSessionStartHooks(sess: sess, turnContext: turn)
        XCTAssertFalse(first)
        sess.replaceResetHistory()
        let afterClear = await runPendingSessionStartHooks(sess: sess, turnContext: turn)
        XCTAssertFalse(afterClear)
        let written = (try? String(
            contentsOf: temp.appendingPathComponent("source.txt"),
            encoding: .utf8
        )) ?? ""
        XCTAssertEqual(
            written.split(whereSeparator: \.isNewline).map(String.init),
            ["startup", "clear"]
        )
    }

    func testBuiltToolsExposesRouterSpecsAndPromptUsesThem() {
        let spec = CurrentTimeHandler().spec()
        let step = StepContext(
            turn: TurnContext(),
            toolRouter: ToolRouter(
                registry: HarnessToolRegistry(),
                modelVisibleSpecs: [spec],
                toolMode: .direct,
                canManageChildren: false
            )
        )
        XCTAssertEqual(builtTools(stepContext: step), [.object(["name": .string(spec.name())])])
        let prompt = buildPrompt(input: [], stepContext: step, baseInstructions: BaseInstructions())
        XCTAssertEqual(prompt.tools, [.object(["name": .string(spec.name())])])
    }

    func testPrepareToolRecommendationsCountsPlugins() {
        let sess = Session()
        sess.services.availablePlugins = [
            PluginCapabilitySummary(configName: "weather", displayName: "Weather"),
        ]
        let prepared = prepareToolRecommendations(sess: sess, turnContext: TurnContext())
        XCTAssertEqual(prepared.endpointCandidateCount, 1)
        XCTAssertFalse(prepared.authPresent)
    }

    func testMaybeRecordCurrentTimeReminderInsertsFragment() throws {
        var config = Config()
        config.features.enable(.currentTimeReminder)
        config.currentTimeReminder = CurrentTimeReminderConfig(intervalSeconds: 0)
        let sess = Session()
        let turn = TurnContext(config: config)
        try maybeRecordCurrentTimeReminder(
            sess: sess,
            turnContext: turn,
            windowId: "w1",
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let prompt = sess.cloneHistory().forPrompt()
        XCTAssertTrue(prompt.contains { item in
            if case .message(_, _, let content, _, _) = item {
                return content.contains { part in
                    if case .inputText(let text) = part {
                        return text.contains("<current_time_reminder>")
                    }
                    return false
                }
            }
            return false
        })
    }

    func testMailboxPreemptsCommentaryWhenMailIsPending() async throws {
        let sess = Session()
        sess.inputQueue.enqueueMailboxCommunication(
            InterAgentCommunication(
                author: AgentPath.root(),
                recipient: try AgentPath.root().join("worker"),
                otherRecipients: [],
                content: "mail",
                triggerTurn: false
            )
        )
        var client: ModelClientSession?
        sess.runSamplingStreamOverride = { _ in
            makeResponseStream([
                .success(.created(responseId: "resp-1")),
                .success(.serverReasoningIncluded(true)),
                .success(.outputItemDone(.message(
                    id: nil,
                    role: "assistant",
                    content: [.outputText(text: "thinking aloud")],
                    phase: .commentary,
                    internalChatMessageMetadataPassthrough: nil
                ))),
                .success(.completed(
                    responseId: "r6",
                    tokenUsage: nil,
                    usageMetadata: nil,
                    endTurn: true
                )),
            ])
        }
        let result = try await tryRunSamplingRequest(
            sess: sess,
            stepContext: StepContext(),
            clientSession: &client,
            prompt: Prompt(),
            cancellationToken: CancellationToken()
        )
        XCTAssertTrue(result.needsFollowUp)
        XCTAssertEqual(sess.lastResponseId, "resp-1")
        XCTAssertTrue(sess.state.serverReasoningIncluded)
        XCTAssertEqual(result.lastAgentMessage, "thinking aloud")
        XCTAssertTrue(sess.emittedEvents.contains { event in
            if case .itemCompleted(let completed) = event,
               case .agentMessage(let message) = completed.item {
                return message.phase == .commentary
            }
            return false
        })
    }

    func testParseTurnItemMapsAssistantAndReasoning() {
        let assistant = parseTurnItem(.message(
            id: .fromServer("msg_1"),
            role: "assistant",
            content: [.outputText(text: "hi")],
            phase: .finalAnswer,
            internalChatMessageMetadataPassthrough: nil
        ))
        guard case .agentMessage(let message) = assistant else {
            return XCTFail("expected agent message")
        }
        XCTAssertEqual(message.id, "msg_1")
        XCTAssertEqual(message.phase, .finalAnswer)

        let reasoning = parseTurnItem(.reasoning(
            id: .fromServer("rsn_1"),
            summary: [.summaryText(text: "think")],
            content: [.reasoningText(text: "raw")],
            encryptedContent: nil,
            internalChatMessageMetadataPassthrough: nil
        ))
        guard case .reasoning(let item) = reasoning else {
            return XCTFail("expected reasoning")
        }
        XCTAssertEqual(item.summaryText, ["think"])
        XCTAssertEqual(item.rawContent, ["raw"])
    }

    func testSafetyBufferingAndToolCallDeltasAreRecorded() async throws {
        let sess = Session()
        var client: ModelClientSession?
        sess.runSamplingStreamOverride = { _ in
            makeResponseStream([
                .success(.safetyBuffering(SafetyBuffering(
                    useCases: ["latency"],
                    reasons: ["queue"],
                    showBufferingUi: true,
                    fasterModel: "fast"
                ))),
                .success(.outputItemAdded(.functionCall(
                    id: .fromServer("fc_1"),
                    name: "apply_patch",
                    namespace: nil,
                    arguments: "",
                    encryptedFunctionArgs: nil,
                    callId: "call_1",
                    internalChatMessageMetadataPassthrough: nil
                ))),
                .success(.toolCallInputDelta(itemId: "fc_1", callId: "call_1", delta: "***")),
                .success(.reasoningSummaryPartAdded(summaryIndex: 2)),
                .success(.reasoningSummaryDone(itemId: "rsn", text: "done thinking", summaryIndex: 2)),
                .success(.outputItemDone(.message(
                    id: .fromServer("msg_2"),
                    role: "assistant",
                    content: [.outputText(text: "ok")],
                    phase: nil,
                    internalChatMessageMetadataPassthrough: nil
                ))),
                .success(.completed(
                    responseId: "r7",
                    tokenUsage: nil,
                    usageMetadata: nil,
                    endTurn: true
                )),
            ])
        }
        _ = try await tryRunSamplingRequest(
            sess: sess,
            stepContext: StepContext(),
            clientSession: &client,
            prompt: Prompt(),
            cancellationToken: CancellationToken()
        )
        XCTAssertEqual(sess.lastSafetyBuffering?.fasterModel, "fast")
        XCTAssertEqual(sess.lastToolCallInputDeltas.map(\.delta), ["***"])
        XCTAssertEqual(sess.lastReasoningSummaryPartIndex, 2)
        XCTAssertTrue(sess.emittedEvents.contains { event in
            if case .safetyBuffering(let buffering) = event {
                return buffering.fasterModel == "fast"
            }
            return false
        })
        XCTAssertTrue(sess.emittedEvents.contains { event in
            if case .agentReasoningSectionBreak(let breakEvent) = event {
                return breakEvent.summaryIndex == 2
            }
            return false
        })
        XCTAssertTrue(sess.emittedEvents.contains { event in
            if case .agentReasoning(let reasoning) = event {
                return reasoning.text == "done thinking"
            }
            return false
        })
        XCTAssertTrue(sess.emittedEvents.contains { event in
            if case .itemCompleted(let completed) = event,
               case .agentMessage(let message) = completed.item {
                return message.id == "msg_2"
            }
            return false
        })
    }

    func testAssembleToolRouterFillsDefaultSpecs() {
        let step = StepContext()
        XCTAssertNil(step.toolRouter)
        let tools = builtTools(sess: Session(), stepContext: step)
        XCTAssertFalse(tools.isEmpty)
        XCTAssertNotNil(step.toolRouter)
    }

    func testExtensionContributorsAppendInjectionItems() async {
        final class RecordingContributor: TurnInputContributor {
            func contribute(userInput: [UserInput], turnId: String) async -> [ResponseItem] {
                _ = userInput
                _ = turnId
                return [
                    .message(
                        id: nil,
                        role: "developer",
                        content: [.inputText(text: "<extension>")],
                        phase: nil,
                        internalChatMessageMetadataPassthrough: nil
                    )
                ]
            }
        }
        let sess = Session()
        sess.services.turnInputContributors = [RecordingContributor()]
        let built = await buildSkillsAndPlugins(
            sess: sess,
            stepContext: StepContext(),
            userInput: [.text(text: "hi", textElements: [])],
            mentionedPlugins: [],
            cancellationToken: CancellationToken()
        )
        XCTAssertTrue(built?.0.contains { item in
            if case .message(_, let role, let content, _, _) = item, role == "developer" {
                return content.contains { part in
                    if case .inputText(let text) = part { return text.contains("<extension>") }
                    return false
                }
            }
            return false
        } == true)
    }

    func testApplyPatchInputDeltaEmitsUpdatedEvent() async throws {
        var config = Config()
        config.features.enable(.applyPatchStreamingEvents)
        let sess = Session()
        var client: ModelClientSession?
        let patch = """
        *** Begin Patch
        *** Add File: foo.txt
        +hello
        *** End Patch

        """
        sess.runSamplingStreamOverride = { _ in
            makeResponseStream([
                .success(.outputItemAdded(.customToolCall(
                    id: .fromServer("fc_1"),
                    status: nil,
                    callId: "call_1",
                    name: "apply_patch",
                    namespace: nil,
                    input: "",
                    internalChatMessageMetadataPassthrough: nil
                ))),
                .success(.toolCallInputDelta(itemId: "fc_1", callId: "call_1", delta: patch)),
                .success(.outputItemDone(.message(
                    id: .fromServer("msg_3"),
                    role: "assistant",
                    content: [.outputText(text: "patched")],
                    phase: nil,
                    internalChatMessageMetadataPassthrough: nil
                ))),
                .success(.completed(
                    responseId: "r8",
                    tokenUsage: nil,
                    usageMetadata: nil,
                    endTurn: true
                )),
            ])
        }
        _ = try await tryRunSamplingRequest(
            sess: sess,
            stepContext: StepContext(turn: TurnContext(config: config)),
            clientSession: &client,
            prompt: Prompt(),
            cancellationToken: CancellationToken()
        )
        XCTAssertTrue(sess.emittedEvents.contains { event in
            if case .patchApplyUpdated(let updated) = event {
                if case .add(let content) = updated.changes["foo.txt"] {
                    return content.contains("hello")
                }
            }
            return false
        })
    }

    func testBuiltToolsIncludesMcpToolNames() {
        let sess = Session()
        sess.services.mcpVisibleTools = [
            McpVisibleTool(name: "linear.search", description: "Search Linear issues", serverName: "linear"),
        ]
        let step = StepContext()
        let router = assembleToolRouter(sess: sess, stepContext: step)
        XCTAssertTrue(router.modelVisibleSpecs.contains { spec in
            spec.name() == "linear.search"
        })
        XCTAssertTrue(builtTools(sess: sess, stepContext: step).contains(.object(["name": .string("linear.search")])))
    }

    func testAssembleToolRouterDecodesMcpCatalogSchema() {
        let sess = Session()
        sess.services.mcpVisibleTools = [
            McpVisibleTool(
                name: "linear.search",
                description: "Search Linear issues",
                serverName: "linear",
                parametersJSON: #"{"type":"object","properties":{"query":{"type":"string"}},"required":["query"],"additionalProperties":false}"#
            ),
        ]
        let router = assembleToolRouter(sess: sess, stepContext: StepContext())
        guard case .function(let tool) = router.modelVisibleSpecs.first(where: { $0.name() == "linear.search" }) else {
            return XCTFail("expected linear.search function spec")
        }
        XCTAssertEqual(tool.parameters.required, ["query"])
        XCTAssertEqual(tool.parameters.properties?["query"]?.schemaType, .single(.string))
        XCTAssertEqual(tool.parameters.additionalProperties, .boolean(false))
        XCTAssertNotNil(router.registry.entry(for: ToolName(plain: "linear.search")))
        XCTAssertEqual(sess.services.mcpHandlerCache.exposedToolNames, ["linear.search"])
    }

    func testAssembleToolRouterRegistersMcpHandlerDispatch() async {
        let sess = Session()
        sess.services.mcpVisibleTools = [
            McpVisibleTool(name: "linear.search", description: "Search Linear issues", serverName: "linear"),
        ]
        let router = assembleToolRouter(sess: sess, stepContext: StepContext())
        do {
            _ = try await router.dispatch(
                ToolCall(
                    toolName: ToolName(plain: "linear.search"),
                    callId: "c1",
                    payload: .function(arguments: "{}"),
                    encryptedFunctionArgs: nil
                )
            )
            XCTFail("expected unwired MCP handler")
        } catch {
            XCTAssertTrue(String(describing: error).contains("not wired"))
        }
    }

    func testAssembleToolRouterOmitsAppsAndHiddenTools() {
        let sess = Session()
        sess.services.appsEnabled = false
        sess.services.mcpVisibleTools = [
            McpVisibleTool(name: "linear.search", serverName: "linear"),
            McpVisibleTool(
                name: "calendar_list_events",
                serverName: CODEX_APPS_MCP_SERVER_NAME,
                connectorId: "calendar"
            ),
            McpVisibleTool(
                name: "hidden.search",
                serverName: "linear",
                visibility: ["app"]
            ),
        ]
        let router = assembleToolRouter(sess: sess, stepContext: StepContext())
        XCTAssertNotNil(router.registry.entry(for: ToolName(plain: "linear.search")))
        XCTAssertNil(router.registry.entry(for: ToolName(plain: "calendar_list_events")))
        XCTAssertNil(router.registry.entry(for: ToolName(plain: "hidden.search")))
        XCTAssertEqual(sess.services.mcpHandlerCache.exposedToolNames, ["linear.search"])
    }

    func testAssembleToolRouterRegistersAdmittedDynamicTools() async throws {
        let lookup = DynamicToolSpec.function(
            DynamicToolFunctionSpec(name: "lookup", description: "Look up", inputSchema: .object([:]))
        )
        let hidden = DynamicToolSpec.function(
            DynamicToolFunctionSpec(
                name: "hidden_lookup",
                description: "Hidden",
                inputSchema: .object([:]),
                deferLoading: true
            )
        )
        let reserved = DynamicToolSpec.function(
            DynamicToolFunctionSpec(
                name: "shell_command", description: "Reserved", inputSchema: .object([:])
            )
        )
        let docs = DynamicToolSpec.namespace(
            DynamicToolNamespaceSpec(
                name: "docs",
                description: "Docs",
                tools: [
                    .function(DynamicToolFunctionSpec(
                        name: "zeta", description: "Z", inputSchema: .object([:]))),
                    .function(DynamicToolFunctionSpec(
                        name: "alpha", description: "A", inputSchema: .object([:]))),
                ]
            )
        )
        let sess = Session()
        sess.state.sessionConfiguration.dynamicTools = [lookup, hidden, reserved, docs]
        let turn = sess.newTurnContext()
        sess.state.sessionConfiguration.dynamicTools = []
        XCTAssertEqual(turn.dynamicTools, [lookup, hidden, reserved, docs])
        let step = StepContext(turn: turn)
        let router = assembleToolRouter(sess: sess, stepContext: step)
        XCTAssertNotNil(router.registry.entry(for: ToolName(plain: "lookup")))
        XCTAssertNotNil(router.registry.entry(for: ToolName(plain: "hidden_lookup")))
        XCTAssertNil(router.registry.entry(for: ToolName(plain: "shell_command")))
        XCTAssertNotNil(router.registry.entry(for: ToolName(namespace: "docs", name: "alpha")))
        XCTAssertTrue(router.modelVisibleSpecs.contains { $0.name() == "lookup" })
        XCTAssertFalse(router.modelVisibleSpecs.contains { $0.name() == "hidden_lookup" })
        let namespaces = router.modelVisibleSpecs.compactMap { spec -> ResponsesApiNamespace? in
            if case .namespace(let namespace) = spec, namespace.name == "docs" { return namespace }
            return nil
        }
        XCTAssertEqual(namespaces.count, 1)
        XCTAssertEqual(namespaces.first?.tools.map(\.function.name), ["alpha", "zeta"])

        let output = try await ToolCallRuntime(session: sess, stepContext: step).handleToolCall(
            ToolCall(
                toolName: ToolName(namespace: "docs", name: "alpha"),
                callId: "call-alpha",
                payload: .function(arguments: #"{"q":"sage"}"#)
            ),
            cancellationToken: CancellationToken()
        )
        guard case .functionCallOutput(_, let callId, _, _, let payload, _) = output else {
            return XCTFail("expected function call output")
        }
        XCTAssertEqual(callId, "call-alpha")
        XCTAssertEqual(
            payload.body.toText(),
            "dynamic tool call was cancelled before receiving a response"
        )
        let started = try XCTUnwrap(
            dynamicToolCalls(in: sess, callId: "call-alpha", status: .inProgress).first)
        XCTAssertEqual(started.namespace, "docs")
        XCTAssertEqual(started.tool, "alpha")
        XCTAssertEqual(started.arguments, .object(["q": .string("sage")]))
    }

    func testAssembleToolRouterRegistersSageExecuteTools() {
        let sess = Session()
        sess.services.sageToolNames = ["list_directory", "read_text_file"]
        let router = assembleToolRouter(sess: sess, stepContext: StepContext())
        XCTAssertNotNil(router.registry.entry(for: ToolName(plain: "list_directory")))
        XCTAssertNotNil(router.registry.entry(for: ToolName(plain: "read_text_file")))
    }

    func testToolCallRuntimeForwardsSageExecuteCall() async throws {
        let sess = Session()
        sess.services.sageToolNames = ["list_directory"]
        sess.services.onSageToolCall = { name, callId, arguments in
            "ok:\(name):\(callId):\(arguments)"
        }
        let step = StepContext()
        _ = assembleToolRouter(sess: sess, stepContext: step)
        let output = try await ToolCallRuntime(session: sess, stepContext: step).handleToolCall(
            ToolCall(
                toolName: ToolName(plain: "list_directory"),
                callId: "c1",
                payload: .function(arguments: "{}"),
                encryptedFunctionArgs: nil
            ),
            cancellationToken: CancellationToken()
        )
        guard case .functionCallOutput(_, let callId, _, _, let payload, _) = output else {
            return XCTFail("expected function call output")
        }
        XCTAssertEqual(callId, "c1")
        XCTAssertEqual(payload.body.toText(), "ok:list_directory:c1:{}")
    }

    func testToolCallRuntimeForwardsSessionMcpCall() async throws {
        let sess = Session()
        sess.services.mcpVisibleTools = [
            McpVisibleTool(name: "linear.search", serverName: "linear"),
        ]
        sess.services.onMcpCall = { name, callId, _ in
            "ok:\(name):\(callId)"
        }
        let step = StepContext()
        _ = assembleToolRouter(sess: sess, stepContext: step)
        let output = try await ToolCallRuntime(session: sess, stepContext: step).handleToolCall(
            ToolCall(
                toolName: ToolName(plain: "linear.search"),
                callId: "c1",
                payload: .function(arguments: "{}"),
                encryptedFunctionArgs: nil
            ),
            cancellationToken: CancellationToken()
        )
        guard case .functionCallOutput(_, let callId, _, _, let payload, _) = output else {
            return XCTFail("expected function call output")
        }
        XCTAssertEqual(callId, "c1")
        XCTAssertEqual(payload.body.toText(), "ok:linear.search:c1")
    }

    func testToolRouterToolSupportsParallelMatchesRuntime() {
        let sess = Session()
        sess.services.sageToolNames = ["list_directory", "write_text_file"]
        let router = assembleToolRouter(sess: sess, stepContext: StepContext())
        XCTAssertTrue(
            router.toolSupportsParallel(
                ToolCall(
                    toolName: ToolName(plain: "list_directory"),
                    callId: "r1",
                    payload: .function(arguments: "{}"),
                    encryptedFunctionArgs: nil
                )
            )
        )
        XCTAssertFalse(
            router.toolSupportsParallel(
                ToolCall(
                    toolName: ToolName(plain: "write_text_file"),
                    callId: "w1",
                    payload: .function(arguments: "{}"),
                    encryptedFunctionArgs: nil
                )
            )
        )
    }

    func testToolCallRuntimeSerializesWrites() async throws {
        let probe = ToolAdmissionProbe()
        let runtime = try makeSageToolRuntime(
            names: ["write_text_file"],
            onCall: { _, _, _ in
                await probe.enter()
                try? await Task.sleep(for: .milliseconds(80))
                await probe.leave()
                return "ok"
            }
        )
        async let first = runtime.handleToolCall(
            sageToolCall("write_text_file", id: "w1"),
            cancellationToken: CancellationToken()
        )
        async let second = runtime.handleToolCall(
            sageToolCall("write_text_file", id: "w2"),
            cancellationToken: CancellationToken()
        )
        _ = try await (first, second)
        let writePeak = await probe.peak
        XCTAssertEqual(writePeak, 1)
    }

    func testToolCallRuntimeOverlapsParallelReads() async throws {
        let probe = ToolAdmissionProbe()
        let runtime = try makeSageToolRuntime(
            names: ["list_directory"],
            onCall: { _, _, _ in
                await probe.enter()
                let deadline = ContinuousClock.now + .milliseconds(400)
                while await probe.peak < 2, ContinuousClock.now < deadline {
                    try? await Task.sleep(for: .milliseconds(5))
                }
                try? await Task.sleep(for: .milliseconds(20))
                await probe.leave()
                return "ok"
            }
        )
        async let first = runtime.handleToolCall(
            sageToolCall("list_directory", id: "r1"),
            cancellationToken: CancellationToken()
        )
        async let second = runtime.handleToolCall(
            sageToolCall("list_directory", id: "r2"),
            cancellationToken: CancellationToken()
        )
        _ = try await (first, second)
        let readPeak = await probe.peak
        XCTAssertGreaterThanOrEqual(readPeak, 2)
    }

    func testToolCallRuntimeWriteExcludesOverlappingRead() async throws {
        let probe = ToolAdmissionProbe()
        let runtime = try makeSageToolRuntime(
            names: ["write_text_file", "list_directory"],
            onCall: { _, _, _ in
                await probe.enter()
                try? await Task.sleep(for: .milliseconds(80))
                await probe.leave()
                return "ok"
            }
        )
        async let write = runtime.handleToolCall(
            sageToolCall("write_text_file", id: "w1"),
            cancellationToken: CancellationToken()
        )
        async let read = runtime.handleToolCall(
            sageToolCall("list_directory", id: "r1"),
            cancellationToken: CancellationToken()
        )
        _ = try await (write, read)
        let mixedPeak = await probe.peak
        XCTAssertEqual(mixedPeak, 1)
    }

    @MainActor
    func testSessionServicesSharesAllowlistApprovalStore() {
        let allowlist = SessionToolAllowlist()
        let sess = Session()
        sess.services.approvalStore = allowlist.approvalStore
        let key = ApprovalStore.sessionCacheKey(name: "write_text_file", argumentsJSON: "{}")
        allowlist.approvalStore.put(key, .approvedForSession)
        XCTAssertTrue(sess.services.approvalStore === allowlist.approvalStore)
        XCTAssertEqual(sess.services.approvalStore?.get(key), .approvedForSession)
    }

    func testInputQueueMailboxAndSteerActivity() async throws {
        let inputQueue = InputQueue()
        let (_, nonePending) = inputQueue.subscribeActivity()
        XCTAssertNil(nonePending)

        let mailOne = try turnLoopMail("one", triggerTurn: false)
        let mailTwo = try turnLoopMail("two", triggerTurn: false)
        let stream = inputQueue.subscribeActivityStream()
        let mailboxTask = Task { () -> InputQueueActivity? in
            for await activity in stream {
                return activity
            }
            return nil
        }
        try await Task.sleep(for: .milliseconds(10))
        inputQueue.enqueueMailboxCommunication(mailOne)
        inputQueue.enqueueMailboxCommunication(mailTwo)
        let mailboxActivity = await mailboxTask.value
        XCTAssertEqual(mailboxActivity, .mailbox)
        let drained = inputQueue.drainMailboxInputItems().0
        XCTAssertEqual(drained, [
            .interAgentCommunication(mailOne),
            .interAgentCommunication(mailTwo),
        ])
        XCTAssertFalse(inputQueue.hasPendingMailboxItems())

        let turnState = TurnState()
        inputQueue.extendPendingInputForTurnState(
            turnState,
            input: [
                .responseItem(
                    .functionCallOutput(
                        id: nil,
                        callId: "n",
                        name: "notify",
                        namespace: nil,
                        output: FunctionCallOutputPayload(body: .text("passive")),
                        internalChatMessageMetadataPassthrough: nil
                    )
                )
            ]
        )
        XCTAssertNil(inputQueue.subscribeActivity(turnState: turnState).1)
        inputQueue.extendPendingInputAndAcceptMailboxDeliveryForTurnState(
            turnState,
            input: [TurnInputBuilder.user([.text(text: "already pending", textElements: [])])]
        )
        XCTAssertEqual(inputQueue.subscribeActivity(turnState: turnState).1, .steer)

        let queued = try turnLoopMail("queued", triggerTurn: false)
        let trigger = try turnLoopMail("wake", triggerTurn: true)
        let triggerQueue = InputQueue()
        triggerQueue.enqueueMailboxCommunication(queued)
        XCTAssertFalse(triggerQueue.hasTriggerTurnMailboxItems())
        triggerQueue.enqueueMailboxCommunication(trigger)
        XCTAssertTrue(triggerQueue.hasTriggerTurnMailboxItems())

        let parent = "a"
        let peer = "b"
        let root = "r"
        let root2 = "s"
        let parentCases: [([(Bool, String?, String?)], String?, String?)] = [
            ([], nil, nil),
            ([(false, "q", root)], nil, nil),
            ([(true, "", root)], nil, nil),
            ([(true, "   ", root)], nil, nil),
            ([(true, nil, root)], nil, nil),
            ([(true, parent, nil)], parent, nil),
            ([(true, parent, "")], parent, nil),
            ([(true, parent, root), (true, peer, root)], nil, root),
            ([(true, parent, root), (true, peer, root2)], nil, root),
            ([(true, parent, root), (true, nil, root)], nil, root),
            ([(true, parent, root), (true, parent, root)], parent, root),
            ([(false, "q", root2), (true, parent, root)], parent, root),
        ]
        for (mails, expectedParent, expectedRoot) in parentCases {
            let queue = InputQueue()
            for (triggerTurn, parentTurnId, rootTurnId) in mails {
                queue.enqueueMailboxCommunication(
                    try turnLoopMail("task", triggerTurn: triggerTurn),
                    startOptions: TurnStartOptions(
                        parentTurnId: parentTurnId,
                        rootTurnId: rootTurnId
                    )
                )
            }
            let startOptions = queue.drainMailboxInputItems().1
            XCTAssertEqual(startOptions.parentTurnId, expectedParent)
            XCTAssertEqual(startOptions.rootTurnId, expectedRoot)
        }

        let latestChoices: [CyberAccessProgram?] = [.standard, nil]
        for latest in latestChoices {
            let queue = InputQueue()
            for (triggerTurn, program) in [
                (true, CyberAccessProgram.daybreakBlue),
                (true, latest),
                (false, CyberAccessProgram.daybreakRed),
            ] as [(Bool, CyberAccessProgram?)] {
                queue.enqueueMailboxCommunication(
                    try turnLoopMail("task", triggerTurn: triggerTurn),
                    startOptions: TurnStartOptions(cyberAccessProgram: program)
                )
            }
            XCTAssertEqual(queue.drainMailboxInputItems().1.cyberAccessProgram, latest)
        }

        let delivery = AgentDeliveryState()
        let caller = ThreadId()
        _ = delivery.enqueue(
            threadId: caller,
            input: .message(message: .plaintext("mail"), mode: .queueOnly)
        )
        let mailboxOutcome = await waitForV2Activity(
            delivery: delivery,
            threadId: caller,
            inputQueue: InputQueue(),
            hasPendingSteer: false,
            timeout: .milliseconds(20)
        )
        XCTAssertEqual(mailboxOutcome, .mailboxActivity)

        let steered = await waitForV2Activity(
            delivery: AgentDeliveryState(),
            threadId: ThreadId(),
            inputQueue: InputQueue(),
            hasPendingSteer: true,
            timeout: .milliseconds(20)
        )
        XCTAssertEqual(steered, .steered)

        let preferredQueue = InputQueue()
        preferredQueue.enqueueMailboxCommunication(try turnLoopMail("mail", triggerTurn: false))
        let preferredDelivery = AgentDeliveryState()
        let preferredCaller = ThreadId()
        _ = preferredDelivery.enqueue(
            threadId: preferredCaller,
            input: .message(message: .plaintext("mail"), mode: .queueOnly)
        )
        let preferredOutcome = await waitForV2Activity(
            delivery: preferredDelivery,
            threadId: preferredCaller,
            inputQueue: preferredQueue,
            hasPendingSteer: true,
            timeout: .milliseconds(20)
        )
        XCTAssertEqual(preferredOutcome, .steered)
    }
}

private func trackSleepProcess(on sess: Session, processId: Int32) async throws -> BackgroundTerminalHandle {
    let spawned = try await spawnPipeProcess(
        program: "/bin/sleep",
        args: ["30"],
        cwd: FileManager.default.currentDirectoryPath,
        env: [:]
    )
    return try await sess.services.unifiedExecManager.trackSpawnedProcess(
        processId: processId,
        callId: "call-\(processId)",
        command: "sleep 30",
        cwd: FileManager.default.currentDirectoryPath,
        spawned: spawned
    )
}

private func userConfig(
    _ layer: [String: UserConfigValue],
    _ path: String...
) -> UserConfigValue? {
    var current: UserConfigValue? = .table(layer)
    for part in path {
        guard case .table(let table)? = current else { return nil }
        current = table[part]
    }
    return current
}

private func patchApprovalRequests(
    in sess: Session,
    callId: String
) -> [ApplyPatchApprovalRequestEvent] {
    sess.emittedEvents.compactMap { event in
        if case .applyPatchApprovalRequest(let request) = event, request.callId == callId {
            return request
        }
        return nil
    }
}

private func execApprovalRequests(
    in sess: Session,
    callId: String
) -> [ExecApprovalRequestEvent] {
    sess.emittedEvents.compactMap { event in
        if case .execApprovalRequest(let request) = event, request.callId == callId {
            return request
        }
        return nil
    }
}

private final class PermissionCallbackFlag: @unchecked Sendable {
    var value = false
}

private let projectRootsAndTmpdirArguments = """
{"environment_id":"workspace","permissions":{"file_system":{"entries":[{"path":{"type":"special","value":{"kind":"project_roots","subpath":"src"}},"access":"write"},{"path":{"type":"special","value":{"kind":"tmpdir"}},"access":"read"}]}}}
"""

private func requestPermissionsToolResponse(
    session: Session,
    environment: TurnEnvironment,
    callId: String,
    arguments: String
) async throws -> RequestPermissionsResponse {
    var registry = HarnessToolRegistry()
    registry.register(RequestPermissionsHandler())
    let step = StepContext(
        toolRouter: ToolRouter(
            registry: registry,
            modelVisibleSpecs: [],
            toolMode: .direct,
            canManageChildren: false
        )
    )
    step.environments = [environment]
    let output = try await ToolCallRuntime(session: session, stepContext: step).handleToolCall(
        ToolCall(
            toolName: ToolName(plain: "request_permissions"),
            callId: callId,
            payload: .function(arguments: arguments)
        ),
        cancellationToken: CancellationToken()
    )
    guard case .functionCallOutput(_, _, _, _, let payload, _) = output else {
        throw PermissionToolOutputError()
    }
    return try JSONDecoder().decode(
        RequestPermissionsResponse.self, from: Data((payload.body.toText() ?? "").utf8))
}

private struct PermissionToolOutputError: Error {}

private func requestPermissionEventCount(_ sess: Session, callId: String? = nil) -> Int {
    sess.emittedEvents.filter { event in
        guard case .requestPermissions(let requested) = event else { return false }
        return callId == nil || requested.callId == callId
    }.count
}

private func permissionPathText(_ entry: FileSystemSandboxEntry) -> String {
    let path: String
    if case .path(let uri) = entry.path {
        path = uri.inferredNativePathString()
    } else {
        path = String(describing: entry.path)
    }
    return "\(entry.access.rawValue) \(path)"
}

private func dynamicToolCalls(
    in sess: Session,
    callId: String,
    status: DynamicToolCallStatus
) -> [DynamicToolCallItem] {
    sess.emittedEvents.compactMap { event in
        let item: TurnItem?
        switch event {
        case .itemStarted(let started):
            item = started.item
        case .itemCompleted(let completed):
            item = completed.item
        default:
            item = nil
        }
        guard case .dynamicToolCall(let call)? = item, call.id == callId, call.status == status else {
            return nil
        }
        return call
    }
}

private final class McpConnectLog: @unchecked Sendable {
    private let lock = NSLock()
    private var ensuredCount = 0
    private var reconnectedCount = 0
    private var disconnectedNames: [String] = []
    private var events: [String] = []

    func ensure() {
        lock.lock()
        ensuredCount += 1
        events.append("ensure")
        lock.unlock()
    }

    func reconnect() {
        lock.lock()
        reconnectedCount += 1
        events.append("reconnect")
        lock.unlock()
    }

    func disconnect(_ names: [String]) {
        lock.lock()
        disconnectedNames.append(contentsOf: names)
        events.append("disconnect:" + names.joined(separator: ","))
        lock.unlock()
    }

    var ensured: Int {
        lock.lock()
        defer { lock.unlock() }
        return ensuredCount
    }

    var reconnected: Int {
        lock.lock()
        defer { lock.unlock() }
        return reconnectedCount
    }

    var disconnected: [String] {
        lock.lock()
        defer { lock.unlock() }
        return disconnectedNames
    }

    var trace: [String] {
        lock.lock()
        defer { lock.unlock() }
        return events
    }
}

final class CapabilityStoreDisconnectTests: XCTestCase {
    func testDisconnectServersMatchesNameAndDoesNotPersist() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("sage-mcp-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("mcp.json")
        let snapshot = MCPFileSnapshot(mcpServers: [
            MCPServerConfig(id: "srv-id", name: "old", command: "/usr/bin/false", enabled: true),
            MCPServerConfig(id: "gone-id", name: "gone", command: "/usr/bin/false", enabled: false),
        ])
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: file)
        let hub = CapabilityStore(store: MCPConfigStore(fileURL: file))
        await hub.reloadMCPConfigs()
        await hub.disconnectServers(["old"])
        let servers = await hub.mcpServers
        let old = try XCTUnwrap(servers.first { $0.id == "srv-id" })
        XCTAssertTrue(old.enabled)
        XCTAssertEqual(old.status, .disconnected)
        XCTAssertEqual(old.toolCount, 0)
        let gone = try XCTUnwrap(servers.first { $0.id == "gone-id" })
        XCTAssertFalse(gone.enabled)
        XCTAssertEqual(gone.status, .disabled)
        let saved = try Data(contentsOf: file)
        XCTAssertEqual(saved, data)
    }
}

private func rolloutTextMessage(_ role: String, _ text: String) -> ResponseItem {
    .message(
        id: nil,
        role: role,
        content: [.inputText(text: text)],
        phase: nil,
        internalChatMessageMetadataPassthrough: nil
    )
}

private func rolloutFunctionOutput(_ text: String) -> RolloutItem {
    .responseItem(CodexHistory.ResponseItemEnvelope(item: .functionCallOutput(
        id: nil,
        callId: "call-1",
        name: "shell",
        namespace: nil,
        output: .fromText(text),
        internalChatMessageMetadataPassthrough: nil
    )))
}

private func restoredOutputTexts(_ history: ContextManager) -> [String] {
    history.items.compactMap { envelope in
        switch envelope.item {
        case .functionCallOutput(_, _, _, _, let output, _):
            return output.textContent
        case .customToolCallOutput(_, _, _, let output, _):
            return output.textContent
        default:
            return nil
        }
    }
}

private func rolloutMessage(_ role: String, _ text: String) -> RolloutItem {
    .responseItem(CodexHistory.ResponseItemEnvelope(item: rolloutTextMessage(role, text)))
}

private func rolloutMessageTexts(_ history: ContextManager) -> [String] {
    history.items.compactMap { envelope in
        guard case .message(_, _, let content, _, _) = envelope.item else { return nil }
        for part in content {
            if case .inputText(let text) = part { return text }
        }
        return nil
    }
}

private func deniedGuardianAssessment(
    status: GuardianAssessmentStatus = .denied
) -> GuardianAssessmentEvent {
    GuardianAssessmentEvent(
        id: "review-1",
        status: status,
        action: .command(source: .shell, command: "ls", cwd: .fromString("/tmp"))
    )
}

private func expectedApprovedGuardianActionText() -> String {
    """
    The user has manually approved a specific action that was previously `Rejected`.

    Treat this as approval to perform that exact action in the same context in which it was originally requested.
    Do not assume this also authorizes similar operations with different payloads.

    Approved action:
    {
      "action": {
        "command": "ls",
        "cwd": "/tmp",
        "source": "shell",
        "type": "command"
      },
      "outcome": "allowed"
    }
    """
}

private func elicitationRequests(in session: Session) -> [ElicitationRequestEvent] {
    session.emittedEvents.compactMap { event in
        if case .elicitationRequest(let request) = event { return request }
        return nil
    }
}

private func elicitationIsPaused(_ session: Session) async -> Bool {
    var iterator = session.services.elicitations.subscribe().makeAsyncIterator()
    return await iterator.next() ?? false
}

private func waitUntil(
    timeout: Duration = .seconds(1),
    _ condition: () -> Bool
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while !condition() {
        if clock.now >= deadline {
            throw CocoaError(.userCancelled)
        }
        try await Task.sleep(for: .milliseconds(10))
    }
}

private func messageContent(_ item: ResponseItem) -> [ContentItem] {
    if case .message(_, _, let content, _, _) = item { return content }
    return []
}

private actor ToolAdmissionProbe {
    private(set) var current = 0
    private(set) var peak = 0

    func enter() {
        current += 1
        peak = max(peak, current)
    }

    func leave() {
        current = max(0, current - 1)
    }
}

private func sessionStartContextCount(_ sess: Session, _ text: String) -> Int {
    sess.cloneHistory().forPrompt().filter { item in
        if case .message(_, let role, let content, _, _) = item, role == "user" {
            return content.contains { part in
                if case .inputText(let partText) = part {
                    return partText == text
                }
                return false
            }
        }
        return false
    }.count
}

private func sageToolCall(_ name: String, id: String) -> ToolCall {
    ToolCall(
        toolName: ToolName(plain: name),
        callId: id,
        payload: .function(arguments: "{}"),
        encryptedFunctionArgs: nil
    )
}

private final class AfterAgentProbe: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var callCount = 0
    private(set) var inputMessages: [String] = []
    private(set) var lastAssistant: String?

    func record(_ event: HookEventAfterAgent) {
        lock.lock()
        callCount += 1
        inputMessages = event.inputMessages
        lastAssistant = event.lastAssistantMessage
        lock.unlock()
    }
}

private func makeSageToolRuntime(
    names: [String],
    onCall: @escaping @Sendable (String, String, String) async -> String?
) throws -> ToolCallRuntime {
    let sess = Session()
    sess.services.sageToolNames = names
    sess.services.onSageToolCall = onCall
    let step = StepContext()
    _ = assembleToolRouter(sess: sess, stepContext: step)
    return ToolCallRuntime(session: sess, stepContext: step)
}

private func turnLoopMail(_ content: String, triggerTurn: Bool) throws -> InterAgentCommunication {
    InterAgentCommunication(
        author: AgentPath.root(),
        recipient: try AgentPath.root().join("worker"),
        otherRecipients: [],
        content: content,
        triggerTurn: triggerTurn
    )
}
