@testable import CodexCore
@testable import Sage
import CodexAPI
import CodexAsyncUtils
import CodexModelProviderInfo
import CodexProtocol
import XCTest

final class ExecuteHarnessModelClientRequestTests: XCTestCase {
    func testPrepareResponseItemsForRequestDropsUnprefixedIds() throws {
        let client = try makeClient()
        var items: [ResponseItem] = [
            .message(
                id: .fromServer("bare"),
                role: "assistant",
                content: [.outputText(text: "hi")],
                phase: nil,
                internalChatMessageMetadataPassthrough: nil
            ),
            .message(
                id: .fromServer("msg_abc"),
                role: "user",
                content: [.inputText(text: "q")],
                phase: nil,
                internalChatMessageMetadataPassthrough: nil
            ),
        ]
        client.prepareResponseItemsForRequest(&items)
        XCTAssertNil(items[0].id())
        XCTAssertEqual(items[1].id()?.asStr, "msg_abc")
    }

    func testPrepareResponseItemsForRequestClearsContentItemKindsUnlessEnabled() throws {
        let client = try makeClient()
        var items: [ResponseItem] = [
            .message(
                id: nil,
                role: "developer",
                content: [.inputText(text: "skill")],
                phase: nil,
                internalChatMessageMetadataPassthrough: InternalChatMessageMetadataPassthrough(
                    contentItemKinds: [ContentItemKind("generic.one")]
                )
            ),
        ]
        client.prepareResponseItemsForRequest(&items)
        XCTAssertNil(items[0].internalChatMessageMetadataPassthrough()?.contentItemKinds)

        client.contentItemKindsEnabled = true
        items = [
            .message(
                id: nil,
                role: "developer",
                content: [.inputText(text: "skill")],
                phase: nil,
                internalChatMessageMetadataPassthrough: InternalChatMessageMetadataPassthrough(
                    contentItemKinds: [ContentItemKind("generic.one")]
                )
            ),
        ]
        client.prepareResponseItemsForRequest(&items)
        XCTAssertEqual(
            items[0].internalChatMessageMetadataPassthrough()?.contentItemKinds,
            [ContentItemKind("generic.one")]
        )
    }

    func testBuildResponsesCompatibilityHeadersAddsMemgenForMemoryConsolidation() throws {
        let client = try makeClient(sessionSource: .internal(.memoryConsolidation))
        var metadata = CodexResponsesMetadata(
            installationId: "inst",
            sessionId: "sess",
            threadId: "thr",
            windowId: "win"
        )
        metadata.requestKind = .turn
        let headers = client.buildResponsesCompatibilityHeaders(metadata)
        XCTAssertEqual(headers[xOpenaiMemgenRequestHeader], "true")
        XCTAssertEqual(headers[xCodexWindowIdHeader], "win")
    }

    func testBuildResponsesOptionsAssemblesLiteTimingAndMetadataHeaders() throws {
        let client = try makeClient()
        client.includeTimingMetrics = true
        client.betaFeaturesHeader = "plan,foo"
        let session = client.newSession()
        var metadata = CodexResponsesMetadata(
            installationId: "inst",
            sessionId: "sess",
            threadId: "thr-meta",
            windowId: "win"
        )
        metadata.requestKind = .turn
        metadata.subagentHeader = "review"
        let options = session.buildResponsesOptions(
            responsesMetadata: metadata,
            useResponsesLite: true
        )
        XCTAssertEqual(options.threadId, "thr-meta")
        XCTAssertEqual(options.extraHeaders[xOpenaiInternalCodexResponsesLiteHeader], "true")
        XCTAssertEqual(options.extraHeaders[xResponsesapiIncludeTimingMetricsHeader], "true")
        XCTAssertEqual(options.extraHeaders["x-codex-beta-features"], "plan,foo")
        XCTAssertEqual(options.extraHeaders[xOpenaiSubagentHeader], "review")
        XCTAssertEqual(options.extraHeaders[xCodexWindowIdHeader], "win")
    }

    func testSanitizeOriginalImageDetailOnItemsDowngradesUnsupportedOriginal() {
        var items: [ResponseItem] = [
            .message(
                id: nil,
                role: "user",
                content: [
                    .inputImage(image: .inline(imageUrl: "data:image/png;base64,aa"), detail: .original),
                ],
                phase: nil,
                internalChatMessageMetadataPassthrough: nil
            ),
        ]
        sanitizeOriginalImageDetailOnItems(canRequestOriginalImageDetail: false, items: &items)
        guard case .message(_, _, let content, _, _) = items[0],
              case .inputImage(_, let detail) = content[0]
        else {
            return XCTFail("expected image message")
        }
        XCTAssertEqual(detail, defaultImageDetail)
    }

    func testStreamRetriesUnauthorizedOnceAfterAuthRecover() async throws {
        let client = try makeClient()
        let recover = RecoverCounter(succeeds: true)
        client.recoverFromUnauthorized = { await recover.call() }
        let session = client.newSession()
        var attempts = 0
        session.streamRequestOverride = { _, _ in
            attempts += 1
            if attempts == 1 {
                throw ApiError.transport(.http(
                    status: 401,
                    url: nil,
                    headers: nil,
                    body: "unauthorized",
                    retryAfter: nil
                ))
            }
            return emptyAPIStream()
        }
        _ = try await session.stream(
            prompt: Prompt(),
            modelInfo: try modelInfoFixture(),
            responsesMetadata: streamMetadata()
        )
        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(recover.count, 1)
    }

    func testStreamDoesNotRetryUnauthorizedWhenRecoverFails() async throws {
        let client = try makeClient()
        let recover = RecoverCounter(succeeds: false)
        client.recoverFromUnauthorized = { await recover.call() }
        let session = client.newSession()
        var attempts = 0
        session.streamRequestOverride = { _, _ in
            attempts += 1
            throw ApiError.transport(.http(
                status: 401,
                url: nil,
                headers: nil,
                body: "unauthorized",
                retryAfter: nil
            ))
        }
        do {
            _ = try await session.stream(
                prompt: Prompt(),
                modelInfo: try modelInfoFixture(),
                responsesMetadata: streamMetadata()
            )
            XCTFail("expected unauthorized")
        } catch let error as CodexErr {
            guard case .unexpectedStatus(let status) = error.details else {
                return XCTFail("expected unexpectedStatus, got \(error)")
            }
            XCTAssertEqual(status.status, 401)
        }
        XCTAssertEqual(attempts, 1)
        XCTAssertEqual(recover.count, 1)
    }

    func testStreamPropagatesConnectionFailureWithoutRetry() async throws {
        let client = try connectionClient(maxRetries: 1)
        let session = client.newSession()
        var attempts = 0
        session.streamRequestOverride = { _, _ in
            attempts += 1
            throw ApiError.transport(.connection(HttpError(message: "offline")))
        }
        do {
            _ = try await session.stream(
                prompt: Prompt(),
                modelInfo: try modelInfoFixture(),
                responsesMetadata: streamMetadata()
            )
            XCTFail("expected connection failure")
        } catch let error as CodexErr {
            guard case .connectionFailed = error.details else {
                return XCTFail("expected connectionFailed, got \(error)")
            }
        }
        XCTAssertEqual(attempts, 1)
    }

    func testResponsesWebsocketEnabledFollowsProviderAndFallback() throws {
        let client = try makeClient()
        XCTAssertFalse(client.responsesWebsocketEnabled())
        XCTAssertFalse(client.forceHttpFallback())
        client.disableWebsockets = false
        XCTAssertTrue(client.responsesWebsocketEnabled())
        XCTAssertTrue(client.forceHttpFallback())
        XCTAssertFalse(client.responsesWebsocketEnabled())

        var info = ModelProviderInfo.createOpenaiProvider("https://api.openai.com/v1")
        info.supportsWebsockets = false
        let plain = CodexCore.ModelClient(
            threadId: ThreadId(),
            providerInfo: info,
            auth: BearerAuthProvider(apiKey: "sk-test")
        )
        plain.disableWebsockets = false
        XCTAssertFalse(plain.responsesWebsocketEnabled())
        XCTAssertFalse(plain.forceHttpFallback())
    }

    func testSamplingRetriesConnectionFailureThenSucceeds() async throws {
        let client = try connectionClient(maxRetries: 1)
        let sess = Session()
        sess.services.modelClient = client
        var attempts = 0
        sess.runSamplingStreamOverride = { _ in
            attempts += 1
            if attempts == 1 {
                throw CodexErr.connectionFailed(
                    ConnectionFailedError(source: HttpError(message: "offline"))
                )
            }
            return makeResponseStream([
                .success(.completed(
                    responseId: "resp_1",
                    tokenUsage: nil,
                    usageMetadata: nil,
                    endTurn: true
                )),
            ])
        }
        var clientSession: ModelClientSession? = client.newSession()
        let turn = TurnContext(subId: "turn-retry")
        let result = try await runSamplingRequest(
            sess: sess,
            stepContext: StepContext(turn: turn),
            clientSession: &clientSession,
            input: [],
            cancellationToken: CancellationToken()
        )
        XCTAssertEqual(attempts, 2)
        XCTAssertFalse(result.needsFollowUp)
        let messages = sess.emittedEvents.compactMap { event -> String? in
            if case .error(let error) = event { return error.message }
            return nil
        }
        XCTAssertTrue(messages.contains { $0.contains("Reconnecting... 1/1") })
    }

    func testSamplingReturnsOriginalErrorWhenRetryBudgetIsZero() async throws {
        let client = try connectionClient(maxRetries: 0)
        let sess = Session()
        sess.services.modelClient = client
        var session = client.newSession()
        var attempts = 0
        session.streamRequestOverride = { _, _ in
            attempts += 1
            throw ApiError.transport(.connection(HttpError(message: "offline")))
        }
        var clientSession: ModelClientSession? = session
        let turn = TurnContext(subId: "turn-exhausted")
        do {
            _ = try await runSamplingRequest(
                sess: sess,
                stepContext: StepContext(turn: turn),
                clientSession: &clientSession,
                input: [],
                cancellationToken: CancellationToken()
            )
            XCTFail("expected connection failure")
        } catch let error as CodexErr {
            guard case .connectionFailed = error.details else {
                return XCTFail("expected connectionFailed, got \(error)")
            }
        }
        XCTAssertEqual(attempts, 1)
        XCTAssertEqual(sess.services.exhaustedResponseRetry?.turnId, "turn-exhausted")
        XCTAssertNil(sess.services.exhaustedResponseRetry?.retryAt)
    }

    func testSamplingSkipsUnboundedRetriesOnBedrock() async throws {
        let client = try connectionClient(maxRetries: 0, name: "Amazon Bedrock")
        let sess = Session()
        sess.features.enable(.unboundedConnectionRetries)
        sess.services.modelClient = client
        var session = client.newSession()
        var attempts = 0
        session.streamRequestOverride = { _, _ in
            attempts += 1
            throw ApiError.transport(.connection(HttpError(message: "offline")))
        }
        var clientSession: ModelClientSession? = session
        do {
            _ = try await runSamplingRequest(
                sess: sess,
                stepContext: StepContext(turn: TurnContext(subId: "turn-bedrock")),
                clientSession: &clientSession,
                input: [],
                cancellationToken: CancellationToken()
            )
            XCTFail("expected connection failure")
        } catch let error as CodexErr {
            guard case .connectionFailed = error.details else {
                return XCTFail("expected connectionFailed, got \(error)")
            }
        }
        XCTAssertEqual(attempts, 1)
    }

    func testStreamThrowsContextWindowWithoutRetry() async throws {
        let client = try makeClient()
        let session = client.newSession()
        var attempts = 0
        session.streamRequestOverride = { _, _ in
            attempts += 1
            throw ApiError.contextWindowExceeded
        }
        do {
            _ = try await session.stream(
                prompt: Prompt(),
                modelInfo: try modelInfoFixture(),
                responsesMetadata: streamMetadata()
            )
            XCTFail("expected context window")
        } catch let error as CodexErr {
            XCTAssertEqual(error.details, .contextWindowExceeded)
        }
        XCTAssertEqual(attempts, 1)
    }
}

private final class RecoverCounter: @unchecked Sendable {
    let succeeds: Bool
    var count = 0

    init(succeeds: Bool) {
        self.succeeds = succeeds
    }

    func call() async -> Bool {
        count += 1
        return succeeds
    }
}

private func streamMetadata() -> CodexResponsesMetadata {
    var metadata = CodexResponsesMetadata(
        installationId: "inst",
        sessionId: "sess",
        threadId: "thr",
        windowId: "win"
    )
    metadata.turnId = "turn-1"
    metadata.requestKind = .turn
    return metadata
}

private func emptyAPIStream() -> CodexAPI.ResponseStream {
    CodexAPI.ResponseStream(
        events: AsyncStream { continuation in
            continuation.finish()
        }
    )
}

private func connectionClient(maxRetries: UInt64, name: String = "OpenAI") throws -> CodexCore.ModelClient {
    var info = ModelProviderInfo.createOpenaiProvider("https://api.openai.com/v1")
    info.name = name
    info.streamMaxRetriesOverride = maxRetries
    return CodexCore.ModelClient(
        threadId: ThreadId(),
        providerInfo: info,
        auth: BearerAuthProvider(apiKey: "sk-test")
    )
}

private func modelInfoFixture() throws -> ModelInfo {
    let json = """
    {
      "slug": "gpt-5",
      "display_name": "GPT-5",
      "supported_reasoning_levels": [],
      "shell_type": "unified_exec",
      "visibility": "list",
      "supported_in_api": true,
      "priority": 0,
      "support_verbosity": true,
      "truncation_policy": { "mode": "tokens", "limit": 1000 },
      "experimental_supported_tools": []
    }
    """
    return try JSONDecoder().decode(ModelInfo.self, from: Data(json.utf8))
}

private func makeClient(
    sessionSource: SessionSource = .cli
) throws -> CodexCore.ModelClient {
    CodexCore.ModelClient(
        threadId: ThreadId(),
        providerInfo: ModelProviderInfo.createOpenaiProvider("https://api.openai.com/v1"),
        sessionSource: sessionSource,
        auth: BearerAuthProvider(apiKey: "sk-test")
    )
}
