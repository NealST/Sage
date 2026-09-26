//
//  Phase6ClientTests.swift
//  SageTests
//
//  Sage addition (no codex counterpart).
//  Phase 6 model-client / SSE / provider catalog tests.
//

import CodexAPI
import CodexCore
import CodexModelProviderInfo
import CodexProtocol
import Foundation
import XCTest

final class Phase6ClientTests: XCTestCase {
    func testWebSearchActionDetail() {
        XCTAssertEqual(
            webSearchActionDetail(.search(query: "codex port", queries: nil)),
            "codex port"
        )
        XCTAssertEqual(
            webSearchActionDetail(.search(query: nil, queries: ["one", "two"])),
            "one ..."
        )
        XCTAssertEqual(
            webSearchActionDetail(.openPage(url: "https://example.com")),
            "https://example.com"
        )
        XCTAssertEqual(
            webSearchActionDetail(.findInPage(url: "https://ex", pattern: "foo")),
            "'foo' in https://ex"
        )
    }

    func testNormalizeImageDetailForResponsesLite() throws {
        var info = try modelInfoFixture()
        info.useResponsesLite = true
        let prompt = Prompt(input: [
            .message(
                id: nil,
                role: "user",
                content: [.inputImage(image: .inline(imageUrl: "data:image/png;base64,aa"), detail: .high)],
                phase: nil,
                internalChatMessageMetadataPassthrough: nil
            )
        ])
        let formatted = prompt.getFormattedInputForRequest(modelInfo: info)
        if case .message(_, _, let content, _, _) = formatted[0],
           case .inputImage(_, let detail) = content[0]
        {
            XCTAssertNil(detail)
        } else {
            XCTFail("expected message with image")
        }
    }

    func testValidateAndFilterExtraMetadata() {
        XCTAssertNoThrow(try validateExtraMetadata(["foo": "bar"]).get())
        XCTAssertThrowsError(try validateExtraMetadata(["session_id": "x"]).get())
        XCTAssertEqual(filterExtraMetadata(["session_id": "x", "ok": "1"])["ok"], "1")
        XCTAssertNil(filterExtraMetadata(["session_id": "x", "ok": "1"])["session_id"])
    }

    func testSubagentHeaderValues() {
        XCTAssertEqual(subagentHeaderValue(.subAgent(.review)), "review")
        XCTAssertEqual(subagentHeaderValue(.subAgent(.compact)), "compact")
        XCTAssertEqual(subagentHeaderValue(.cli), nil)
        XCTAssertEqual(subagentMetadataKind(.subAgent(.threadSpawn(
            parentThreadId: ThreadId(), depth: 1, agentPath: nil,
            agentNickname: nil, agentRole: nil
        ))), "thread_spawn")
    }

    func testProcessResponsesEventOutputTextDelta() throws {
        let event = ResponsesStreamEvent(kind: "response.output_text.delta", delta: "hello")
        let parsed = try processResponsesEvent(event)
        XCTAssertEqual(parsed, .outputTextDelta("hello"))
    }

    func testProcessResponsesEventCompleted() throws {
        let event = ResponsesStreamEvent(
            kind: "response.completed",
            response: .object([
                "id": .string("resp_1"),
                "usage": .object([
                    "input_tokens": .int(3),
                    "output_tokens": .int(2),
                    "total_tokens": .int(5),
                ]),
            ])
        )
        let parsed = try processResponsesEvent(event)
        guard case .completed(let id, let usage, _, _) = parsed else {
            return XCTFail("expected completed")
        }
        XCTAssertEqual(id, "resp_1")
        XCTAssertEqual(usage?.totalTokens, 5)
    }

    func testProcessResponsesEventFailedContextWindow() {
        let event = ResponsesStreamEvent(
            kind: "response.failed",
            response: .object([
                "error": .object([
                    "code": .string("context_length_exceeded"),
                    "message": .string("too long"),
                ]),
            ])
        )
        XCTAssertThrowsError(try processResponsesEvent(event)) { error in
            XCTAssertEqual(error as? ApiError, .contextWindowExceeded)
        }
    }

    func testAzureProviderDetection() {
        XCTAssertTrue(isAzureResponsesProvider(name: "Azure", baseUrl: "https://example.com"))
        XCTAssertTrue(isAzureResponsesProvider(
            name: "test",
            baseUrl: "https://foo.openai.azure.com/openai"
        ))
        XCTAssertFalse(isAzureResponsesProvider(
            name: "test",
            baseUrl: "https://api.openai.com/v1"
        ))
    }

    func testBuiltInProvidersIncludeOpenAIAndOSS() {
        let providers = builtInModelProviders(nil)
        XCTAssertNotNil(providers[OPENAI_PROVIDER_ID])
        XCTAssertNotNil(providers[OLLAMA_OSS_PROVIDER_ID])
        XCTAssertEqual(providers[OPENAI_PROVIDER_ID]?.wireApi, .responses)
        XCTAssertTrue(providers[OPENAI_PROVIDER_ID]?.requiresOpenaiAuth ?? false)
    }

    func testCreateTextParamAndResponsesRequest() throws {
        let text = createTextParamForRequest(
            verbosity: .low,
            outputSchema: .object(["type": .string("object")]),
            outputSchemaStrict: true
        )
        XCTAssertEqual(text?.verbosity, .low)
        XCTAssertEqual(text?.format?.name, "codex_output_schema")

        let info = try modelInfoFixture()
        let client = ModelClient(
            threadId: ThreadId(),
            providerInfo: ModelProviderInfo.createOpenaiProvider("https://api.openai.com/v1"),
            auth: BearerAuthProvider(apiKey: "sk-test")
        )
        var metadata = CodexResponsesMetadata(
            installationId: "inst",
            sessionId: "sess",
            threadId: "thr",
            windowId: "win"
        )
        metadata.requestKind = .turn
        let request = client.buildResponsesRequest(
            prompt: Prompt(
                input: [
                    .message(
                        id: nil, role: "user",
                        content: [.inputText(text: "hi")],
                        phase: nil,
                        internalChatMessageMetadataPassthrough: nil
                    )
                ],
                baseInstructions: BaseInstructions(text: "Be brief")
            ),
            modelInfo: info,
            effort: .low,
            summary: .auto,
            serviceTier: nil,
            responsesMetadata: metadata,
            includeInternal: true
        )
        XCTAssertEqual(request.model, info.slug)
        XCTAssertEqual(request.instructions, "Be brief")
        XCTAssertEqual(request.toolChoice, "auto")
        XCTAssertFalse(request.store)
        XCTAssertTrue(request.stream)
        XCTAssertEqual(request.clientMetadata?["session_id"], "sess")
        XCTAssertFalse(client.responsesWebsocketEnabled())
    }

    func testResolveSystemTimeProvider() throws {
        let provider = try resolveTimeProvider(clockSource: .system, externalProvider: nil)
        XCTAssertTrue(provider is SystemTimeProvider)
        XCTAssertThrowsError(try resolveTimeProvider(clockSource: .external, externalProvider: nil))
    }

    func testCanRequestOriginalImageDetail() throws {
        var info = try modelInfoFixture()
        info.supportsImageDetailOriginal = true
        XCTAssertTrue(canRequestOriginalImageDetail(info))
        var items: [FunctionCallOutputContentItem] = [
            .inputImage(image: .inline(imageUrl: "data:image/png;base64,aa"), detail: .original)
        ]
        sanitizeOriginalImageDetail(canRequestOriginalImageDetail: false, items: &items)
        if case .inputImage(_, let detail) = items[0] {
            XCTAssertEqual(detail, defaultImageDetail)
        } else {
            XCTFail("expected image")
        }
    }
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
