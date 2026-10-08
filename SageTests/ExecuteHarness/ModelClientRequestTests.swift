@testable import CodexCore
import CodexAPI
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

    func testStreamRetriesConnectionFailureThenSucceeds() async throws {
        var info = ModelProviderInfo.createOpenaiProvider("https://api.openai.com/v1")
        info.streamMaxRetriesOverride = 1
        let client = ModelClient(
            threadId: ThreadId(),
            providerInfo: info,
            auth: BearerAuthProvider(apiKey: "sk-test")
        )
        let session = client.newSession()
        var attempts = 0
        session.streamRequestOverride = { _, _ in
            attempts += 1
            if attempts == 1 {
                throw ApiError.transport(.connection(HttpError(message: "offline")))
            }
            return emptyAPIStream()
        }
        _ = try await session.stream(
            prompt: Prompt(),
            modelInfo: try modelInfoFixture(),
            responsesMetadata: streamMetadata()
        )
        XCTAssertEqual(attempts, 2)
        XCTAssertFalse(session.lastStreamRetryMessages.isEmpty)
    }

    func testStreamThrowsRetryLimitAfterConnectionRetriesExhaust() async throws {
        var info = ModelProviderInfo.createOpenaiProvider("https://api.openai.com/v1")
        info.streamMaxRetriesOverride = 0
        let client = ModelClient(
            threadId: ThreadId(),
            providerInfo: info,
            auth: BearerAuthProvider(apiKey: "sk-test")
        )
        let session = client.newSession()
        session.streamRequestOverride = { _, _ in
            throw ApiError.transport(.connection(HttpError(message: "offline")))
        }
        do {
            _ = try await session.stream(
                prompt: Prompt(),
                modelInfo: try modelInfoFixture(),
                responsesMetadata: streamMetadata()
            )
            XCTFail("expected retryLimit")
        } catch let error as CodexErr {
            guard case .retryLimit = error.details else {
                return XCTFail("expected retryLimit, got \(error)")
            }
        }
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
) throws -> ModelClient {
    ModelClient(
        threadId: ThreadId(),
        providerInfo: ModelProviderInfo.createOpenaiProvider("https://api.openai.com/v1"),
        sessionSource: sessionSource,
        auth: BearerAuthProvider(apiKey: "sk-test")
    )
}
