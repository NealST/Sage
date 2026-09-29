@testable import Sage
import CodexAsyncUtils
import CodexCore
import CodexProtocol
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

    func testBuildSkillsAndPluginsInjectsSkillAndPluginItems() async {
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
        sess.runSamplingStreamOverride = { _ in
            makeResponseStream([
                .success(.outputTextDelta("intro <proposed_plan>step one</proposed_plan>")),
                .success(.outputItemDone(.message(
                    id: nil,
                    role: "assistant",
                    content: [.outputText(text: "intro <proposed_plan>step one</proposed_plan>")],
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
        let again = await runPendingSessionStartHooks(sess: sess, turnContext: turn)
        XCTAssertFalse(again)
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

private func messageContent(_ item: ResponseItem) -> [ContentItem] {
    if case .message(_, _, let content, _, _) = item { return content }
    return []
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
