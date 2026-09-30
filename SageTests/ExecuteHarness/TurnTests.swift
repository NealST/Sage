@testable import Sage
import CodexAPI
import CodexAsyncUtils
import CodexCore
import CodexProtocol
import XCTest

@MainActor
final class ExecuteHarnessTurnTests: XCTestCase {
    private var tempDirectory: URL?

    override func tearDown() async throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        try await super.tearDown()
    }

    func testFinalAnswerWithoutTools() async throws {
        let runtime = try makeRuntime()
        var reply: String?
        runtime.turns.execute.onCandidateReply = { reply = $0 }
        runtime.turns.execute.modelSampler = { includeTools in
            XCTAssertTrue(includeTools)
            return ModelTurn(content: "做好了", toolCalls: [])
        }

        await runtime.turns.execute.start()

        XCTAssertEqual(reply, "做好了")
        XCTAssertEqual(runtime.turns.execute.toolBatchCount, 0)
    }

    func testOneToolRoundThenFinalAnswer() async throws {
        let runtime = try makeRuntime()
        _ = await runtime.taskStore.createAndActivateTask(relatedTo: [])
        var rounds = 0
        var toolRuns = 0
        var reply: String?
        runtime.turns.execute.onCandidateReply = { reply = $0 }
        runtime.turns.execute.modelSampler = { _ in
            rounds += 1
            if rounds == 1 {
                return ModelTurn(
                    content: "先读",
                    toolCalls: [
                        ToolCallProposal(id: "c1", name: "read_text_file", argumentsJSON: "{}"),
                    ]
                )
            }
            return ModelTurn(content: "读完了", toolCalls: [])
        }
        runtime.turns.execute.runToolBatch = { _ in
            toolRuns += 1
            _ = await runtime.taskStore.commit(appendEvents: [], deleteEventIDs: []) { task in
                task.pendingPlan = nil
            }
            runtime.planProgress.clear()
            return .succeeded
        }

        await runtime.turns.execute.start()

        XCTAssertEqual(toolRuns, 1)
        XCTAssertEqual(reply, "读完了")
        XCTAssertEqual(runtime.turns.execute.toolBatchCount, 1)
        XCTAssertNil(runtime.state.activeTask?.pendingPlan)
    }

    func testNineToolRoundsDoNotStopAtTheOldBatchCap() async throws {
        let runtime = try makeRuntime()
        _ = await runtime.taskStore.createAndActivateTask(relatedTo: [])
        var rounds = 0
        var reply: String?
        runtime.turns.execute.onCandidateReply = { reply = $0 }
        runtime.turns.execute.modelSampler = { _ in
            rounds += 1
            if rounds <= 9 {
                return ModelTurn(
                    content: "",
                    toolCalls: [
                        ToolCallProposal(
                            id: "c\(rounds)",
                            name: "read_text_file",
                            argumentsJSON: "{}"
                        ),
                    ]
                )
            }
            return ModelTurn(content: "九轮之后仍能收尾", toolCalls: [])
        }
        runtime.turns.execute.runToolBatch = { _ in .succeeded }

        await runtime.turns.execute.start()

        XCTAssertEqual(reply, "九轮之后仍能收尾")
        XCTAssertEqual(runtime.turns.execute.toolBatchCount, 9)
        XCTAssertTrue(runtime.turns.execute.canOfferMoreTools)
    }

    func testStopCancelsTheModelRequest() async throws {
        let runtime = try makeRuntime()
        var stopped = false
        var reply: String?
        runtime.turns.execute.onCandidateReply = { reply = $0 }
        runtime.turns.execute.handleStop = { _ in
            stopped = true
        }
        runtime.turns.execute.modelSampler = { _ in
            throw CancellationError()
        }

        await runtime.turns.execute.start()

        XCTAssertTrue(stopped)
        XCTAssertNil(reply)
    }

    func testObservePlanRejectsWritesBeforeTheToolRunner() async throws {
        let runtime = try makeRuntime()
        _ = await runtime.taskStore.createAndActivateTask(relatedTo: [])
        _ = await runtime.taskStore.commit(appendEvents: [], deleteEventIDs: []) { task in
            task.workPlan = WorkPlan(
                kind: .observe,
                intent: "看看 README",
                approach: "只读。"
            )
        }
        var rounds = 0
        var toolRuns = 0
        var reply: String?
        runtime.turns.execute.onCandidateReply = { reply = $0 }
        runtime.turns.execute.modelSampler = { _ in
            rounds += 1
            if rounds == 1 {
                return ModelTurn(
                    content: "",
                    toolCalls: [
                        ToolCallProposal(id: "w1", name: "write_text_file", argumentsJSON: "{}"),
                    ]
                )
            }
            return ModelTurn(content: "只看了目录", toolCalls: [])
        }
        runtime.turns.execute.runToolBatch = { _ in
            toolRuns += 1
            return .succeeded
        }

        await runtime.turns.execute.start()

        XCTAssertEqual(toolRuns, 0)
        XCTAssertEqual(reply, "只看了目录")
        let refusal = runtime.state.events.first { $0.kind == .toolResult && $0.toolCallID == "w1" }
        XCTAssertTrue(refusal?.content.hasPrefix("ERROR:") == true)
        XCTAssertTrue(refusal?.content.contains("observe plan") == true)
    }

    func testObservePlanRefusesWritesInsideAMixedBatch() async throws {
        let runtime = try makeRuntime()
        _ = await runtime.taskStore.createAndActivateTask(relatedTo: [])
        _ = await runtime.taskStore.commit(appendEvents: [], deleteEventIDs: []) { task in
            task.workPlan = WorkPlan(
                kind: .observe,
                intent: "看看 README",
                approach: "只读。"
            )
        }
        var rounds = 0
        var toolRuns = 0
        runtime.turns.execute.onCandidateReply = { _ in }
        runtime.turns.execute.modelSampler = { _ in
            rounds += 1
            if rounds > 1 {
                return ModelTurn(content: "只看了目录", toolCalls: [])
            }
            return ModelTurn(
                content: "",
                toolCalls: [
                    ToolCallProposal(id: "r1", name: "read_text_file", argumentsJSON: "{}"),
                    ToolCallProposal(id: "w1", name: "write_text_file", argumentsJSON: "{}"),
                ]
            )
        }
        runtime.turns.execute.runToolBatch = { _ in
            toolRuns += 1
            let names = runtime.planProgress.plan?.steps.map(\.toolName) ?? []
            XCTAssertEqual(names, ["read_text_file"])
            return .succeeded
        }

        await runtime.turns.execute.start()

        XCTAssertEqual(toolRuns, 1)
        let refusal = runtime.state.events.first { $0.kind == .toolResult && $0.toolCallID == "w1" }
        XCTAssertTrue(refusal?.content.hasPrefix("ERROR:") == true)
    }

    func testStartAttachesHarnessSessionWithoutLeavingTurnRun() async throws {
        let runtime = try makeRuntime()
        _ = await runtime.taskStore.createAndActivateTask(relatedTo: [])
        _ = await runtime.taskStore.commit(
            appendEvents: [
                AgentEvent(kind: .userInput, content: "first"),
                AgentEvent(kind: .assistantResponse, content: "ok"),
                AgentEvent(kind: .userInput, content: "again"),
            ],
            deleteEventIDs: []
        ) { _ in }
        var reply: String?
        runtime.turns.execute.onCandidateReply = { reply = $0 }
        runtime.turns.execute.modelSampler = { _ in
            ModelTurn(content: "from-turn-run", toolCalls: [])
        }

        await runtime.turns.execute.start()

        XCTAssertEqual(reply, "from-turn-run")
        XCTAssertFalse(runtime.turns.execute.useHarnessRunTurn)
        XCTAssertEqual(runtime.turns.execute.harnessInput.count, 1)
        XCTAssertEqual(
            runtime.turns.execute.harnessSession?.cloneHistory().forPrompt().count,
            2
        )
    }

    func testHarnessRunTurnDispatchesToolsThenFinishes() async throws {
        let runtime = try makeRuntime()
        _ = await runtime.taskStore.createAndActivateTask(relatedTo: [])
        _ = await runtime.taskStore.commit(
            appendEvents: [AgentEvent(kind: .userInput, content: "list it")],
            deleteEventIDs: []
        ) { _ in }
        var samples = 0
        var invoked: [String] = []
        var reply: String?
        runtime.turns.execute.useHarnessRunTurn = true
        runtime.turns.execute.admitHarnessBatch = { .ready }
        runtime.turns.execute.onCandidateReply = { reply = $0 }
        runtime.turns.execute.modelSampler = { _ in
            samples += 1
            if samples == 1 {
                return ModelTurn(
                    content: nil,
                    toolCalls: [ToolCallProposal(id: "t1", name: "list_directory", argumentsJSON: "{}")]
                )
            }
            return ModelTurn(content: "listed", toolCalls: [])
        }
        runtime.turns.execute.invokeHarnessTool = { call in
            invoked.append(call.name)
            return "listed files"
        }

        await runtime.turns.execute.start()

        XCTAssertEqual(invoked, ["list_directory"])
        XCTAssertEqual(samples, 2)
        XCTAssertEqual(reply, "listed")
        let followUp = runtime.turns.execute.harnessSampleConversations.last
        XCTAssertEqual(
            followUp?.first { $0.kind == .toolResult && $0.toolCallID == "t1" }?.content,
            "listed files"
        )
    }

    func testHarnessRunTurnUsesAttachedSessionAndSampler() async throws {
        let runtime = try makeRuntime()
        _ = await runtime.taskStore.createAndActivateTask(relatedTo: [])
        _ = await runtime.taskStore.commit(
            appendEvents: [AgentEvent(kind: .userInput, content: "hello")],
            deleteEventIDs: []
        ) { _ in }
        var reply: String?
        runtime.turns.execute.useHarnessRunTurn = true
        runtime.turns.execute.onCandidateReply = { reply = $0 }
        runtime.turns.execute.modelSampler = { _ in
            ModelTurn(content: "from-harness", toolCalls: [])
        }

        await runtime.turns.execute.start()

        XCTAssertEqual(reply, "from-harness")
        XCTAssertTrue(runtime.turns.execute.harnessSession?.mcpReprojectionRequested == true)
        XCTAssertTrue(
            runtime.turns.execute.harnessSession?.emittedEvents.contains(where: isTurnComplete)
                == true
        )
    }

    func testHarnessRunTurnPausesWhenTheBatchNeedsApproval() async throws {
        let runtime = try makeRuntime()
        _ = await runtime.taskStore.createAndActivateTask(relatedTo: [])
        _ = await runtime.taskStore.commit(
            appendEvents: [AgentEvent(kind: .userInput, content: "write it")],
            deleteEventIDs: []
        ) { task in
            task.workPlan = WorkPlan(kind: .act, intent: "write a note", approach: "write the file")
        }
        var samples = 0
        var reply: String?
        runtime.turns.execute.useHarnessRunTurn = true
        runtime.turns.execute.admitHarnessBatch = { .paused }
        runtime.turns.execute.onCandidateReply = { reply = $0 }
        runtime.turns.execute.modelSampler = { _ in
            samples += 1
            if samples == 1 {
                return ModelTurn(
                    content: nil,
                    toolCalls: [
                        ToolCallProposal(
                            id: "w1",
                            name: "write_text_file",
                            argumentsJSON: #"{"path":"~/Documents/note.txt","content":"hi"}"#
                        ),
                    ]
                )
            }
            return ModelTurn(content: "wrote", toolCalls: [])
        }

        await runtime.turns.execute.start()

        XCTAssertEqual(samples, 1)
        XCTAssertNil(reply)
        XCTAssertEqual(runtime.turns.execute.toolBatchCount, 1)
        XCTAssertNotNil(runtime.state.activeTask?.pendingPlan)
    }

    func testHarnessRunTurnResumesAfterApprovalPause() async throws {
        let runtime = try makeRuntime()
        _ = await runtime.taskStore.createAndActivateTask(relatedTo: [])
        _ = await runtime.taskStore.commit(
            appendEvents: [AgentEvent(kind: .userInput, content: "write it")],
            deleteEventIDs: []
        ) { task in
            task.workPlan = WorkPlan(kind: .act, intent: "write a note", approach: "write the file")
        }
        var samples = 0
        var admits = 0
        var invoked: [String] = []
        var reply: String?
        runtime.turns.execute.useHarnessRunTurn = true
        runtime.turns.execute.admitHarnessBatch = {
            admits += 1
            return admits == 1 ? .paused : .ready
        }
        runtime.turns.execute.onCandidateReply = { reply = $0 }
        runtime.turns.execute.modelSampler = { _ in
            samples += 1
            if samples == 1 {
                return ModelTurn(
                    content: nil,
                    toolCalls: [
                        ToolCallProposal(
                            id: "w1",
                            name: "write_text_file",
                            argumentsJSON: #"{"path":"~/Documents/note.txt","content":"hi"}"#
                        ),
                    ]
                )
            }
            return ModelTurn(content: "wrote", toolCalls: [])
        }
        runtime.turns.execute.invokeHarnessTool = { call in
            invoked.append(call.name)
            return "wrote file"
        }

        await runtime.turns.execute.start()
        XCTAssertEqual(invoked, [])
        XCTAssertNil(reply)

        await runtime.turns.execute.resumePausedBatch(retryFailedSteps: false)

        XCTAssertEqual(invoked, ["write_text_file"])
        XCTAssertEqual(samples, 2)
        XCTAssertEqual(reply, "wrote")
        let result = runtime.state.events.first { $0.kind == .toolResult && $0.toolCallID == "w1" }
        XCTAssertEqual(result?.content, "wrote file")
    }

    func testWorkPlanAppendixStaysOnTheExecutePrompt() async throws {
        let runtime = try makeRuntime()
        _ = await runtime.taskStore.createAndActivateTask(relatedTo: [])
        _ = await runtime.taskStore.commit(appendEvents: [], deleteEventIDs: []) { task in
            task.workPlan = WorkPlan(
                kind: .act,
                intent: "只改 README 的安装节",
                approach: "补一行 brew。"
            )
        }

        let assembly = await runtime.modelGateway.assemblePrompt(
            tools: [],
            workingMemory: nil,
            skillResult: nil
        )
        let system = assembly.events
            .filter { $0.kind == .systemInstruction }
            .map(\.content)
            .joined(separator: "\n")

        XCTAssertTrue(system.contains("Confirmed work plan"))
        XCTAssertTrue(system.contains("只改 README 的安装节"))
    }

    func testCollectedResponsesReplayKeepsUsageAndDropsRefusedCalls() async throws {
        let usage = TokenUsage(inputTokens: 11, outputTokens: 3, totalTokens: 14)
        let message = ResponseItem.message(
            id: nil,
            role: "assistant",
            content: [.outputText(text: "hi")],
            phase: nil,
            internalChatMessageMetadataPassthrough: nil
        )
        let keep = ResponseItem.functionCall(
            id: nil,
            name: "list_directory",
            namespace: nil,
            arguments: "{}",
            encryptedFunctionArgs: nil,
            callId: "c1",
            internalChatMessageMetadataPassthrough: nil
        )
        let drop = ResponseItem.functionCall(
            id: nil,
            name: "write_text_file",
            namespace: nil,
            arguments: "{}",
            encryptedFunctionArgs: nil,
            callId: "c2",
            internalChatMessageMetadataPassthrough: nil
        )
        let stream = makeResponseStream([
            .success(.created(responseId: "resp_live")),
            .success(.outputTextDelta("hi")),
            .success(.outputItemDone(message)),
            .success(.outputItemDone(keep)),
            .success(.toolCallInputDelta(itemId: "item", callId: "c2", delta: "{")),
            .success(.outputItemDone(drop)),
            .success(.completed(
                responseId: "resp_live",
                tokenUsage: usage,
                usageMetadata: nil,
                endTurn: true
            )),
        ])
        let sample = try await ExecuteHarnessAttach.collectResponses(from: stream)
        XCTAssertEqual(sample.turn.content, "hi")
        XCTAssertEqual(sample.turn.toolCalls.map(\.id), ["c1", "c2"])

        let filtered = ExecuteHarnessAttach.filteredEvents(sample.events, allowing: ["c1"])
        let callIDs = filtered.compactMap { event -> String? in
            guard case .success(let value) = event else { return nil }
            guard case .outputItemDone(let item) = value else { return nil }
            guard case .functionCall(_, _, _, _, _, let callID, _) = item else { return nil }
            return callID
        }
        XCTAssertEqual(callIDs, ["c1"])
        XCTAssertFalse(filtered.contains { event in
            guard case .success(.toolCallInputDelta(_, let callID, _)) = event else { return false }
            return callID == "c2"
        })

        let session = Session()
        let textOnly = ExecuteHarnessAttach.filteredEvents(sample.events, allowing: [])
        session.runSamplingStreamOverride = { _ in
            ExecuteHarnessAttach.replay(textOnly, allowing: nil)
        }
        var clientSession: ModelClientSession?
        let result = try await tryRunSamplingRequest(
            sess: session,
            stepContext: StepContext(),
            clientSession: &clientSession,
            prompt: Prompt(),
            cancellationToken: CancellationToken()
        )
        XCTAssertEqual(session.lastResponseId, "resp_live")
        XCTAssertEqual(session.getTotalTokenUsage(), 14)
        XCTAssertEqual(result.lastAgentMessage, "hi")
    }

    func testLiveResponsesYieldsTextBeforeAdmittingTools() async throws {
        let signal = TurnTestSignal()
        let gated = try await ExecuteHarnessAttach.liveResponses(providerStreamWithTwoCalls()) { turn in
            XCTAssertEqual(turn.toolCalls.map(\.id), ["c1", "c2"])
            await signal.wait()
            return .admit(["c1"])
        }
        var labels: [String] = []
        for await event in gated.events {
            switch event {
            case .success(.created):
                labels.append("created")
            case .success(.outputTextDelta):
                labels.append("text")
                signal.fire()
            case .success(.outputItemDone(let item)):
                if case .functionCall(_, _, _, _, _, let callID, _) = item {
                    labels.append(callID)
                } else {
                    labels.append("message")
                }
            case .success(.toolCallInputDelta(_, let callID, _)):
                labels.append("delta-\(callID ?? "")")
            case .success(.completed(_, let usage, _, let endTurn)):
                labels.append("completed")
                XCTAssertEqual(usage?.totalTokens, 14)
                XCTAssertEqual(endTurn, true)
            default:
                break
            }
        }
        XCTAssertEqual(labels, ["created", "text", "message", "c1", "completed"])
    }

    func testLiveResponsesFollowUpKeepsUsageAndSkipsTools() async throws {
        let gated = try await ExecuteHarnessAttach.liveResponses(providerStreamWithTwoCalls()) { _ in
            .followUpWithoutTools
        }
        let session = Session()
        session.runSamplingStreamOverride = { _ in gated }
        var clientSession: ModelClientSession?
        let result = try await tryRunSamplingRequest(
            sess: session,
            stepContext: StepContext(),
            clientSession: &clientSession,
            prompt: Prompt(),
            cancellationToken: CancellationToken()
        )
        XCTAssertTrue(result.needsFollowUp)
        XCTAssertEqual(session.lastResponseId, "resp_live")
        XCTAssertEqual(session.getTotalTokenUsage(), 14)
        XCTAssertEqual(result.lastAgentMessage, "hi")
    }

    func testResponsesStreamBecomesAModelTurn() async throws {
        let stream = ExecuteHarnessAttach.responseStream(from: ModelTurn(
            content: "hi",
            toolCalls: [ToolCallProposal(id: "c1", name: "list_directory", argumentsJSON: "{}")]
        ))
        let turn = try await ExecuteHarnessAttach.modelTurn(from: stream)
        XCTAssertEqual(turn.content, "hi")
        XCTAssertEqual(turn.toolCalls.map(\.name), ["list_directory"])
        XCTAssertEqual(turn.toolCalls.map(\.id), ["c1"])
    }

    func testResponsesClientLeaseStaysOnTheSession() throws {
        let first = ExecuteHarnessAttach.leaseResponsesClient(
            existing: nil,
            baseURL: "https://example.test/v1",
            apiKey: "sk-test"
        )
        let again = ExecuteHarnessAttach.leaseResponsesClient(
            existing: first,
            baseURL: "https://example.test/v1",
            apiKey: "sk-test"
        )
        let rotated = ExecuteHarnessAttach.leaseResponsesClient(
            existing: first,
            baseURL: "https://other.test/v1",
            apiKey: "sk-test"
        )
        let empty = ExecuteHarnessAttach.leaseResponsesClient(
            existing: first,
            baseURL: "",
            apiKey: "sk-test"
        )

        let client = try XCTUnwrap(first?.client)
        XCTAssertTrue(again?.client === client)
        let moved = try XCTUnwrap(rotated?.client)
        XCTAssertFalse(moved === client)
        XCTAssertEqual(client.threadId, moved.threadId)
        XCTAssertNil(empty)

        let session = ExecuteHarnessAttach.makeSession(history: [], threadId: client.threadId)
        session.services.modelClient = client
        let metadata = ExecuteHarnessAttach.responsesMetadata(session: session, turn: nil)
        XCTAssertEqual(metadata.threadId, client.threadId.description)
        XCTAssertEqual(metadata.sessionId, client.threadId.description)
        XCTAssertEqual(metadata.installationId, session.installationId)
        XCTAssertEqual(metadata.requestKind, .turn)
        XCTAssertTrue(session.services.modelClient === client)
    }

    func testSamplingReusesTheClientSessionRunTurnOpened() async throws {
        let session = Session()
        let opened = ExecuteHarnessAttach.responsesClient(
            baseURL: "https://example.test/v1",
            apiKey: "sk-test",
            threadId: session.threadId
        ).newSession()
        var clientSession: ModelClientSession? = opened
        let step = StepContext(turn: TurnContext(model: "gpt-test"))
        session.runSamplingStreamOverride = { _ in
            XCTAssertTrue(session.samplingClientSession === opened)
            XCTAssertEqual(session.samplingStepContext?.turn.subId, step.turn.subId)
            let metadata = session.responsesMetadata(step, requestKind: .turn)
            XCTAssertEqual(metadata.turnId, step.turn.subId)
            XCTAssertEqual(metadata.threadId, session.threadId.description)
            return ExecuteHarnessAttach.responseStream(from: ModelTurn(content: nil, toolCalls: []))
        }
        _ = try await tryRunSamplingRequest(
            sess: session,
            stepContext: step,
            clientSession: &clientSession,
            prompt: Prompt(),
            cancellationToken: CancellationToken()
        )
        XCTAssertTrue(session.samplingClientSession === opened)
    }

    func testRunSamplingRequestSendsPreparedSystemAndTools() async throws {
        let session = Session()
        session.prepareSamplingPrompt = {
            session.state.sessionConfiguration.baseInstructions = "系统"
            session.services.sageResponsesTools = [
                .object([
                    "type": .string("function"),
                    "name": .string("read_text_file"),
                ]),
            ]
        }
        var seenSystem = ""
        var seenTools: [CodexProtocol.JSONValue] = []
        session.runSamplingStreamOverride = { prompt in
            seenSystem = prompt.baseInstructions.text
            seenTools = prompt.tools
            XCTAssertTrue(prompt.parallelToolCalls)
            return ExecuteHarnessAttach.responseStream(from: ModelTurn(content: "ok", toolCalls: []))
        }
        var clientSession: ModelClientSession?
        let result = try await runSamplingRequest(
            sess: session,
            stepContext: StepContext(),
            clientSession: &clientSession,
            input: [],
            cancellationToken: CancellationToken()
        )
        XCTAssertEqual(seenSystem, "系统")
        XCTAssertEqual(seenTools.count, 1)
        XCTAssertEqual(result.lastAgentMessage, "ok")

        session.services.sageResponsesTools = []
        let empty = buildPrompt(
            input: [],
            stepContext: StepContext(),
            baseInstructions: BaseInstructions(text: "系统"),
            sess: session
        )
        XCTAssertTrue(empty.tools.isEmpty)
        XCTAssertFalse(empty.parallelToolCalls)
    }

    func testResponsesEndpointMissingIsOnly404() {
        let missing = CodexErr.unexpectedStatus(
            UnexpectedResponseError(status: 404, body: "no responses route")
        )
        let denied = CodexErr.unexpectedStatus(
            UnexpectedResponseError(status: 401, body: "bad key")
        )
        XCTAssertTrue(ExecuteHarnessAttach.responsesEndpointMissing(missing))
        XCTAssertFalse(ExecuteHarnessAttach.responsesEndpointMissing(denied))
        XCTAssertFalse(ExecuteHarnessAttach.responsesEndpointMissing(CodexErr.stream("closed")))
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
        let runtime = AgentRuntime(
            settings: .shared,
            tools: .makeDefault(),
            taskRepository: repository,
            skills: SkillSessionController()
        )
        runtime.turns.execute.useHarnessRunTurn = false
        return runtime
    }

    private func providerStreamWithTwoCalls() -> CodexCore.ResponseStream {
        let usage = TokenUsage(inputTokens: 11, outputTokens: 3, totalTokens: 14)
        let message = ResponseItem.message(
            id: nil,
            role: "assistant",
            content: [.outputText(text: "hi")],
            phase: nil,
            internalChatMessageMetadataPassthrough: nil
        )
        let keep = ResponseItem.functionCall(
            id: nil,
            name: "list_directory",
            namespace: nil,
            arguments: "{}",
            encryptedFunctionArgs: nil,
            callId: "c1",
            internalChatMessageMetadataPassthrough: nil
        )
        let drop = ResponseItem.functionCall(
            id: nil,
            name: "write_text_file",
            namespace: nil,
            arguments: "{}",
            encryptedFunctionArgs: nil,
            callId: "c2",
            internalChatMessageMetadataPassthrough: nil
        )
        return makeResponseStream([
            .success(.created(responseId: "resp_live")),
            .success(.outputTextDelta("hi")),
            .success(.outputItemDone(message)),
            .success(.outputItemDone(keep)),
            .success(.toolCallInputDelta(itemId: "item", callId: "c2", delta: "{")),
            .success(.outputItemDone(drop)),
            .success(.completed(
                responseId: "resp_live",
                tokenUsage: usage,
                usageMetadata: nil,
                endTurn: true
            )),
        ])
    }

    private func isTurnComplete(_ event: EventMsg) -> Bool {
        switch event {
        case .turnComplete(let _):
            return true
        default:
            return false
        }
    }
}

private final class TurnTestSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false
    private var waiter: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            if fired {
                lock.unlock()
                continuation.resume()
                return
            }
            waiter = continuation
            lock.unlock()
        }
    }

    func fire() {
        lock.lock()
        fired = true
        let waiter = self.waiter
        self.waiter = nil
        lock.unlock()
        waiter?.resume()
    }
}
