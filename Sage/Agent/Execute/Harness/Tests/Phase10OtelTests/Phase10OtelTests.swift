//
//  Phase10OtelTests.swift
//  Phase10OtelTests
//
//  Sage addition (no codex counterpart).
//  Phase 10 otel / terminal-detection / core facade tests.
//

import CodexCore
import CodexOtel
import CodexProtocol
import CodexTerminalDetection
import CodexUtils
import Foundation
import XCTest

final class Phase10OtelTests: XCTestCase {
    func testSystemAliasesResolvesTmp() throws {
        let tmp = try AbsolutePathBuf.fromAbsolutePath("/tmp/sage-otel-alias")
        let normalized = try tmp.normalizeSystemAliases()
        XCTAssertTrue(
            normalized.path.hasPrefix("/private/tmp/") || normalized.path == tmp.path,
            normalized.path
        )
    }

    func testTerminalDetectionPrefersTermProgram() {
        let info = detectTerminalInfo(from: [
            "TERM_PROGRAM": "iTerm.app",
            "TERM_PROGRAM_VERSION": "3.5.0",
            "TERM": "xterm-256color",
        ])
        XCTAssertEqual(info.name, .iterm2)
        XCTAssertEqual(info.termProgram, "iTerm.app")
        XCTAssertEqual(info.version, "3.5.0")
        XCTAssertEqual(info.userAgentToken(), "iTerm.app/3.5.0")
    }

    func testTerminalDetectionTmuxDoesNotMaskKitty() {
        let info = detectTerminalInfo(from: [
            "TERM_PROGRAM": "tmux",
            "TMUX": "1",
            "KITTY_WINDOW_ID": "1",
        ])
        XCTAssertEqual(info.name, .kitty)
        if case .tmux = info.multiplexer {
            // ok
        } else {
            XCTFail("expected tmux multiplexer")
        }
    }

    func testMetricsClientRecordsTurnTimingAndTokens() throws {
        let client = try MetricsClient(
            .inMemory(environment: "test", serviceName: "sage", serviceVersion: "1")
                .withRuntimeReader()
        )
        try client.counter(TURN_TOKEN_USAGE_METRIC, inc: 42, tags: [("kind", "total")])
        try client.recordDuration(TURN_TTFT_DURATION_METRIC, duration: .milliseconds(12))
        let snapshot = try client.snapshot()
        XCTAssertEqual(snapshot.count, 2)
        XCTAssertEqual(snapshot[0].name, TURN_TOKEN_USAGE_METRIC)
        XCTAssertEqual(snapshot[0].value, 42)
        XCTAssertEqual(snapshot[1].name, TURN_TTFT_DURATION_METRIC)
        XCTAssertEqual(snapshot[1].value, 12, accuracy: 0.001)
    }

    func testSessionTelemetryRecordsTokenUsage() throws {
        let client = try MetricsClient(
            .inMemory(environment: "test", serviceName: "sage", serviceVersion: "1")
                .withRuntimeReader()
        )
        var telemetry = SessionTelemetry(
            conversationId: ThreadId(),
            model: "gpt-5",
            slug: "gpt-5",
            originator: "codex_cli_rs",
            logUserPrompts: false,
            terminalType: "unknown",
            sessionSource: .cli
        )
        telemetry = telemetry.withMetrics(client)
        telemetry.recordTokenUsage(
            TokenUsage(inputTokens: 10, outputTokens: 5, totalTokens: 15)
        )
        telemetry.recordTurnTtft(.milliseconds(8))
        let snapshot = try client.snapshot()
        XCTAssertTrue(snapshot.contains { $0.name == TURN_TOKEN_USAGE_METRIC && $0.value == 15 })
        XCTAssertTrue(snapshot.contains { $0.name == TURN_TTFT_DURATION_METRIC })
    }

    func testTelemetryPreviewTruncates() {
        let preview = telemetryPreview(
            String(repeating: "a", count: 80),
            limits: ToolResultLogConfig(maxBytes: 16)
        )
        XCTAssertTrue(preview.truncated)
        XCTAssertTrue(preview.text.contains("[... telemetry preview truncated ...]"))
    }

    func testBuildProviderDisabledReturnsNil() throws {
        let provider = try buildProvider(
            OtelInitInputs(
                environment: "dev",
                serviceName: "sage",
                serviceVersion: "1",
                codexHome: "/tmp",
                analyticsEnabled: false
            )
        )
        XCTAssertNil(provider)
    }

    func testBuildProviderInMemoryMetrics() throws {
        let provider = try buildProvider(
            OtelInitInputs(
                environment: "dev",
                serviceName: "sage",
                serviceVersion: "1",
                codexHome: "/tmp",
                metricsExporter: .otlpHttp(
                    endpoint: "http://127.0.0.1/v1/metrics",
                    headers: [:],
                    protocol: .json,
                    tls: nil
                ),
                analyticsEnabled: true,
                runtimeMetrics: true
            )
        )
        XCTAssertNotNil(provider?.metrics())
        recordProcessStart(provider, originator: "codex_cli_rs")
    }

    func testResponsesMetadataTurnKind() {
        let metadata = responsesMetadata(
            installationId: "inst",
            sessionId: "sess",
            threadId: "thread",
            turnId: "turn-1",
            windowId: "win",
            sessionSource: .cli,
            parentThreadId: nil,
            requestKind: .turn
        )
        XCTAssertEqual(metadata.turnId, "turn-1")
        XCTAssertEqual(metadata.requestKind, .turn)
        let withParent = withParentTurn(metadata, id: "parent-turn")
        XCTAssertEqual(withParent.parentTurnId, "parent-turn")
    }

    func testValidateTracestateAndTraceparent() throws {
        try validateTracestateEntries(["vendor": ["field": "value"]])
        XCTAssertThrowsError(try validateTracestateMember("bad key", fields: [:]))
        XCTAssertNil(contextFromTraceHeaders(traceparent: "not-a-trace", tracestate: nil))
        XCTAssertNotNil(
            contextFromTraceHeaders(
                traceparent: "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01",
                tracestate: nil
            )
        )
    }

    func testBoundedOriginatorAndAuthMode() {
        XCTAssertEqual(boundedOriginatorTagValue("codex_cli_rs"), "codex_cli_rs")
        XCTAssertEqual(boundedOriginatorTagValue("mystery-client"), "other")
        XCTAssertEqual(TelemetryAuthMode(.apiKey), .apiKey)
        XCTAssertEqual(TelemetryAuthMode(.chatgpt), .chatgpt)
    }

    func testConversationManagerAlias() {
        let _: ConversationManager.Type = ThreadManager.self
        let _: NewConversation.Type = NewThread.self
        let _: CodexConversation.Type = CodexThread.self
    }

    func testResponseInputToResponseItem() {
        let output = FunctionCallOutputPayload(body: .text("ok"), success: true)
        let item = responseInputToResponseItem(
            .functionCallOutput(callId: "c1", output: output)
        )
        if case .functionCallOutput(_, let callId, _, _, let payload, _) = item {
            XCTAssertEqual(callId, "c1")
            XCTAssertEqual(payload.body.toText(), "ok")
        } else {
            XCTFail("expected function call output")
        }
        XCTAssertNil(responseInputToResponseItem(
            .message(role: "user", content: [.inputText(text: "hi")], phase: nil)
        ))
    }
}
