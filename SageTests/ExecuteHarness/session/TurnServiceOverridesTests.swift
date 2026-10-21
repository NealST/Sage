@testable import Sage
import SageAPI
import SageAsyncUtils
import SageCore
import SageProtocol
import XCTest

/// S1 of the M3 single-thread topology: `TurnServiceOverrides` lets one turn
/// on a shared session borrow the sampling prompt and tool dispatch without
/// disturbing the session-level slots Execute relies on.
final class TurnServiceOverridesTests: XCTestCase {
    private func completedStream(_ text: String) -> SageCore.ResponseStream {
        makeResponseStream([
            .success(.outputItemDone(.message(
                id: nil,
                role: "assistant",
                content: [.outputText(text: text)],
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

    private func specs(_ names: [String]) -> [SageToolSpec] {
        names.map {
            SageToolSpec(name: $0, description: $0, parameters: .object([:], additionalProperties: true))
        }
    }

    func testTurnBaseInstructionsSkipsSessionPrepare() async throws {
        let sess = Session()
        sess.state.sessionConfiguration.baseInstructions = "session-system"
        let prepareRan = PrepareRan()
        sess.prepareSamplingPrompt = {
            await prepareRan.record()
        }
        var seenSystem = ""
        let turn = TurnContext(serviceOverrides: TurnServiceOverrides(
            baseInstructions: "phase-system",
            runSamplingStreamOverride: { prompt in
                seenSystem = prompt.baseInstructions.text
                return self.completedStream("from-turn")
            }
        ))
        var clientSession: ModelClientSession?
        let result = try await runSamplingRequest(
            sess: sess,
            stepContext: StepContext(turn: turn),
            clientSession: &clientSession,
            input: [],
            cancellationToken: CancellationToken()
        )
        XCTAssertEqual(seenSystem, "phase-system")
        XCTAssertEqual(result.lastAgentMessage, "from-turn")
        let prepareCalls = await prepareRan.count
        XCTAssertEqual(prepareCalls, 0, "turn-level baseInstructions must skip prepareSamplingPrompt")
    }

    func testWithoutOverridesSessionPrepareAndBaseStillApply() async throws {
        let sess = Session()
        let prepareRan = PrepareRan()
        sess.prepareSamplingPrompt = {
            await prepareRan.record()
            sess.state.sessionConfiguration.baseInstructions = "prepared-system"
        }
        var seenSystem = ""
        sess.runSamplingStreamOverride = { prompt in
            seenSystem = prompt.baseInstructions.text
            return ExecuteHarnessAttach.responseStream(from: ModelTurn(content: "ok", toolCalls: []))
        }
        var clientSession: ModelClientSession?
        _ = try await runSamplingRequest(
            sess: sess,
            stepContext: StepContext(turn: TurnContext()),
            clientSession: &clientSession,
            input: [],
            cancellationToken: CancellationToken()
        )
        XCTAssertEqual(seenSystem, "prepared-system")
        let prepareCalls = await prepareRan.count
        XCTAssertEqual(prepareCalls, 1)
    }

    func testTurnStreamOverrideWinsOverSessionSlot() async throws {
        let sess = Session()
        let opened = ExecuteHarnessAttach.responsesClient(
            baseURL: "https://example.test/v1",
            apiKey: "sk-test",
            threadId: sess.threadId
        ).newSession()
        sess.runSamplingStreamOverride = { _ in
            self.completedStream("from-session")
        }
        let turn = TurnContext(serviceOverrides: TurnServiceOverrides(
            runSamplingStreamOverride: { _ in
                self.completedStream("from-turn")
            }
        ))
        var input: [SessionTurnInput] = [
            TurnInputBuilder.user([.text(text: "hi", textElements: [])]),
        ]
        var requirements = McpStartupRequirements()
        let message = try await runTurn(
            sess: sess,
            turnContext: turn,
            input: &input,
            mcpStartupRequirements: &requirements,
            prewarmedClientSession: opened,
            cancellationToken: CancellationToken()
        )
        XCTAssertEqual(message, "from-turn")
        XCTAssertNil(
            sess.samplingClientSession,
            "a turn-level override must not claim the Execute sampling bookkeeping"
        )
    }

    func testSessionStreamOverrideStillClaimsClientSession() async throws {
        let sess = Session()
        let opened = ExecuteHarnessAttach.responsesClient(
            baseURL: "https://example.test/v1",
            apiKey: "sk-test",
            threadId: sess.threadId
        ).newSession()
        sess.runSamplingStreamOverride = { _ in
            self.completedStream("from-session")
        }
        var input: [SessionTurnInput] = [
            TurnInputBuilder.user([.text(text: "hi", textElements: [])]),
        ]
        var requirements = McpStartupRequirements()
        let message = try await runTurn(
            sess: sess,
            turnContext: TurnContext(),
            input: &input,
            mcpStartupRequirements: &requirements,
            prewarmedClientSession: opened,
            cancellationToken: CancellationToken()
        )
        XCTAssertEqual(message, "from-session")
        XCTAssertTrue(sess.samplingClientSession === opened)
    }

    func testTurnOnSageToolCallWinsOverSessionSlot() async throws {
        let sess = Session()
        sess.services.sageToolSpecs = specs(["list_directory"])
        sess.services.onSageToolCall = { _, _, _ in "session-dispatch" }
        let turn = TurnContext(serviceOverrides: TurnServiceOverrides(
            onSageToolCall: { _, _, _ in "turn-dispatch" }
        ))
        let step = StepContext(turn: turn)
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
        XCTAssertEqual(payload.body.toText(), "turn-dispatch")
    }

    func testWithoutOverridesSessionOnSageToolCallStillApplies() async throws {
        let sess = Session()
        sess.services.sageToolSpecs = specs(["list_directory"])
        sess.services.onSageToolCall = { _, _, _ in "session-dispatch" }
        let step = StepContext(turn: TurnContext())
        _ = assembleToolRouter(sess: sess, stepContext: step)
        let output = try await ToolCallRuntime(session: sess, stepContext: step).handleToolCall(
            ToolCall(
                toolName: ToolName(plain: "list_directory"),
                callId: "c2",
                payload: .function(arguments: "{}"),
                encryptedFunctionArgs: nil
            ),
            cancellationToken: CancellationToken()
        )
        guard case .functionCallOutput(_, let callId, _, _, let payload, _) = output else {
            return XCTFail("expected function call output")
        }
        XCTAssertEqual(callId, "c2")
        XCTAssertEqual(payload.body.toText(), "session-dispatch")
    }
}

private actor PrepareRan {
    private(set) var count = 0
    func record() {
        count += 1
    }
}
