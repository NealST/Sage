//
//  session_telemetry.swift
//  CodexOtel
//
//  Port of codex-rs/otel/src/events/session_telemetry.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Metadata + turn timing / token / cost / tool metrics are live.
//  SSE / websocket / Responses span fields wait on CodexAPI and are
//  omitted (plan §Phase 10: turn timing + token usage).
//

import CodexProtocol
import CodexUtils
import Foundation
import os

private let knownProductSkus: Set<String> = ["codex"]
private let sageAppVersion = "0.0.0-sage"

public struct AuthEnvTelemetryMetadata: Equatable, Sendable {
    public var openaiApiKeyEnvPresent: Bool
    public var codexApiKeyEnvPresent: Bool
    public var codexApiKeyEnvEnabled: Bool
    public var providerEnvKeyName: String?
    public var providerEnvKeyPresent: Bool?
    public var refreshTokenUrlOverridePresent: Bool

    public init(
        openaiApiKeyEnvPresent: Bool = false,
        codexApiKeyEnvPresent: Bool = false,
        codexApiKeyEnvEnabled: Bool = false,
        providerEnvKeyName: String? = nil,
        providerEnvKeyPresent: Bool? = nil,
        refreshTokenUrlOverridePresent: Bool = false
    ) {
        self.openaiApiKeyEnvPresent = openaiApiKeyEnvPresent
        self.codexApiKeyEnvPresent = codexApiKeyEnvPresent
        self.codexApiKeyEnvEnabled = codexApiKeyEnvEnabled
        self.providerEnvKeyName = providerEnvKeyName
        self.providerEnvKeyPresent = providerEnvKeyPresent
        self.refreshTokenUrlOverridePresent = refreshTokenUrlOverridePresent
    }
}

public struct SessionTelemetryMetadata: Sendable {
    public var conversationId: ThreadId
    public var agentName: String
    public var authMode: String?
    public var authEnv: AuthEnvTelemetryMetadata
    public var accountId: String?
    public var accountEmail: String?
    public var originator: String
    public var productSku: String?
    public var serviceName: String?
    public var sessionSource: String
    public var model: String
    public var slug: String
    public var serviceTier: String?
    public var modelReasoningEffort: String?
    public var logUserPrompts: Bool
    public var appVersion: String
    public var terminalType: String
}

public struct SessionTelemetry: Sendable {
    var toolResultLogConfig: ToolResultLogConfig
    public var metadata: SessionTelemetryMetadata
    public var metrics: MetricsClient?
    public var metricsUseMetadataTags: Bool

    public func withToolResultLogConfig(_ config: ToolResultLogConfig) -> SessionTelemetry {
        var copy = self
        copy.toolResultLogConfig = config
        return copy
    }

    public func withAuthEnv(_ authEnv: AuthEnvTelemetryMetadata) -> SessionTelemetry {
        var copy = self
        copy.metadata.authEnv = authEnv
        return copy
    }

    public func withModel(_ model: String, slug: String) -> SessionTelemetry {
        var copy = self
        copy.metadata.model = model
        copy.metadata.slug = slug
        return copy
    }

    public func withInferenceRequest(
        serviceTier: String?,
        modelReasoningEffort: String?
    ) -> SessionTelemetry {
        var copy = self
        copy.metadata.serviceTier = serviceTier
        copy.metadata.modelReasoningEffort = modelReasoningEffort
        return copy
    }

    public func withMetricsServiceName(_ serviceName: String) -> SessionTelemetry {
        var copy = self
        copy.metadata.serviceName = sanitizeMetricTagValue(serviceName)
        return copy
    }

    public func withProductSku(_ productSku: String?) -> SessionTelemetry {
        var copy = self
        switch productSku {
        case nil, .some(""):
            copy.metadata.productSku = nil
        case .some(let sku):
            copy.metadata.productSku = knownProductSkus.contains(sku) ? sku : "other"
        }
        return copy
    }

    public func withMetrics(_ metrics: MetricsClient) -> SessionTelemetry {
        var copy = self
        copy.metrics = metrics
        copy.metricsUseMetadataTags = true
        return copy
    }

    public func withMetricsWithoutMetadataTags(_ metrics: MetricsClient) -> SessionTelemetry {
        var copy = self
        copy.metrics = metrics
        copy.metricsUseMetadataTags = false
        return copy
    }

    public func withMetricsConfig(_ config: MetricsConfig) throws -> SessionTelemetry {
        try withMetrics(MetricsClient(config))
    }

    public func withProviderMetrics(_ provider: OtelProvider) -> SessionTelemetry {
        if let metrics = provider.metrics() {
            return withMetrics(metrics)
        }
        return self
    }

    public func counter(_ name: String, inc: Int64, tags: [(String, String)] = []) {
        do {
            guard let metrics else { return }
            try metrics.counter(name, inc: inc, tags: tagsWithMetadata(tags))
        } catch {
            Logger(subsystem: "codex.otel", category: "metrics")
                .warning("metrics counter [\(name, privacy: .public)] failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func histogram(_ name: String, value: Int64, tags: [(String, String)] = []) {
        do {
            guard let metrics else { return }
            try metrics.histogram(name, value: value, tags: tagsWithMetadata(tags))
        } catch {
            Logger(subsystem: "codex.otel", category: "metrics")
                .warning("metrics histogram [\(name, privacy: .public)] failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func histogramWithBoundaries(
        _ name: String,
        value: Int64,
        boundaries: [Double],
        tags: [(String, String)] = []
    ) {
        do {
            guard let metrics else { return }
            try metrics.histogramWithBoundaries(
                name,
                value: value,
                boundaries: boundaries,
                tags: tagsWithMetadata(tags)
            )
        } catch {
            Logger(subsystem: "codex.otel", category: "metrics")
                .warning("metrics histogram [\(name, privacy: .public)] failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func recordDuration(
        _ name: String,
        duration: Duration,
        tags: [(String, String)] = []
    ) {
        do {
            guard let metrics else { return }
            try metrics.recordDuration(name, duration: duration, tags: tagsWithMetadata(tags))
        } catch {
            Logger(subsystem: "codex.otel", category: "metrics")
                .warning("metrics duration [\(name, privacy: .public)] failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func recordMultiAgentSpawnPhase(
        phase: String,
        duration: Duration,
        forkMode: String,
        historyMode: String,
        multiAgentVersion: String
    ) {
        guard let metrics else { return }
        var tags = multiAgentSpawnTags(forkMode: forkMode, multiAgentVersion: multiAgentVersion)
        tags.append(("history_mode", historyMode))
        tags.append(("phase", phase))
        try? metrics.recordDuration(MULTI_AGENT_SPAWN_PHASE_DURATION_METRIC, duration: duration, tags: tags)
    }

    public func recordMultiAgentSpawnFailure(
        reason: String,
        forkMode: String,
        multiAgentVersion: String
    ) {
        guard let metrics else { return }
        var tags = multiAgentSpawnTags(forkMode: forkMode, multiAgentVersion: multiAgentVersion)
        tags.append(("reason", reason))
        try? metrics.counter(MULTI_AGENT_SPAWN_FAILURE_METRIC, inc: 1, tags: tags)
    }

    public func recordStartupPhase(
        phase: String,
        duration: Duration,
        status: String? = nil
    ) {
        var tags = [("phase", phase)]
        if let status {
            tags.append(("status", status))
        }
        recordDuration(STARTUP_PHASE_DURATION_METRIC, duration: duration, tags: tags)
        var fields = [
            "event.name": "codex.startup_phase",
            "startup.phase": phase,
            "duration_ms": String(Int(duration.milliseconds)),
        ]
        if let status {
            fields["startup.status"] = status
        }
        logAndTraceOtelEvent(self, common: fields)
    }

    public func recordTurnTtft(_ duration: Duration) {
        recordDuration(TURN_TTFT_DURATION_METRIC, duration: duration)
        logAndTraceOtelEvent(
            self,
            common: [
                "event.name": "codex.turn_ttft",
                "duration_ms": String(Int(duration.milliseconds)),
            ]
        )
    }

    public func recordTurnE2E(_ duration: Duration) {
        recordDuration(TURN_E2E_DURATION_METRIC, duration: duration)
        logAndTraceOtelEvent(
            self,
            common: [
                "event.name": "codex.turn_e2e",
                "duration_ms": String(Int(duration.milliseconds)),
            ]
        )
    }

    public func recordTokenUsage(_ usage: TokenUsage) {
        histogram(TURN_TOKEN_USAGE_METRIC, value: usage.totalTokens, tags: [("kind", "total")])
        histogram(TURN_TOKEN_USAGE_METRIC, value: usage.inputTokens, tags: [("kind", "input")])
        histogram(TURN_TOKEN_USAGE_METRIC, value: usage.outputTokens, tags: [("kind", "output")])
        logAndTraceOtelEvent(
            self,
            common: [
                "event.name": "codex.turn_token_usage",
                "usage.input_tokens": String(usage.inputTokens),
                "usage.output_tokens": String(usage.outputTokens),
                "usage.total_tokens": String(usage.totalTokens),
            ]
        )
    }

    public func recordTurnCost(
        turnId: String,
        estimatedUsd: String,
        interrupted: Bool,
        speed: String? = nil,
        reasoningEffort: String? = nil
    ) {
        if let microusd = parseEstimatedMicrousd(estimatedUsd) {
            var tags = [
                ("turn.id", turnId),
                ("conversation.id", metadata.conversationId.description),
                ("turn.interrupted", interrupted ? "true" : "false"),
            ]
            if let speed { tags.append(("speed", speed)) }
            if let reasoningEffort { tags.append(("reasoning_effort", reasoningEffort)) }
            counter(TURN_COST_MICROUSD_METRIC, inc: microusd, tags: tags)
        }
        var fields: [String: String] = [
            "event.name": "codex.turn_cost",
            "turn.id": turnId,
            "usage.estimated_usd": estimatedUsd,
            "turn.interrupted": interrupted ? "true" : "false",
        ]
        if let speed { fields["speed"] = speed }
        if let reasoningEffort { fields["reasoning_effort"] = reasoningEffort }
        logOtelEvent(self, fields)
    }

    public func recordPluginInstallElicitationSent(toolType: String, toolId: String) {
        counter(
            PLUGIN_INSTALL_ELICITATION_SENT_METRIC,
            inc: 1,
            tags: [("tool_type", toolType), ("tool_id", toolId)]
        )
    }

    public func recordPluginInstallSuggestion(toolType: String, toolId: String) {
        counter(
            PLUGIN_INSTALL_SUGGESTION_METRIC,
            inc: 1,
            tags: [("tool_type", toolType), ("tool_id", toolId)]
        )
    }

    public func recordToolCall(duration: Duration, success: Bool) {
        counter(TOOL_CALL_COUNT_METRIC, inc: 1, tags: [("success", success ? "true" : "false")])
        recordDuration(TOOL_CALL_DURATION_METRIC, duration: duration)
    }

    public init(
        conversationId: ThreadId,
        model: String,
        slug: String,
        accountId: String? = nil,
        accountEmail: String? = nil,
        authMode: TelemetryAuthMode? = nil,
        originator: String,
        logUserPrompts: Bool,
        terminalType: String,
        sessionSource: SessionSource
    ) {
        let agentName = sessionSource.getAgentPath()?.description
            ?? sessionSource.getNickname()
            ?? (sessionSource.isNonRootAgent() ? conversationId.description : AgentPath.root().description)
        metadata = SessionTelemetryMetadata(
            conversationId: conversationId,
            agentName: agentName,
            authMode: authMode.map(\.rawValue),
            authEnv: AuthEnvTelemetryMetadata(),
            accountId: accountId,
            accountEmail: accountEmail,
            originator: sanitizeMetricTagValue(originator),
            productSku: nil,
            serviceName: nil,
            sessionSource: sessionSourceTelemetryLabel(sessionSource),
            model: model,
            slug: slug,
            serviceTier: nil,
            modelReasoningEffort: nil,
            logUserPrompts: logUserPrompts,
            appVersion: sageAppVersion,
            terminalType: terminalType
        )
        toolResultLogConfig = ToolResultLogConfig()
        metrics = globalMetricsClient()
        metricsUseMetadataTags = true
    }

    func tagsWithMetadata(_ tags: [(String, String)]) throws -> [(String, String)] {
        guard metricsUseMetadataTags else { return tags }
        var combined = try SessionMetricTagValues(
            authMode: metadata.authMode,
            sessionSource: metadata.sessionSource,
            originator: metadata.originator,
            serviceName: metadata.serviceName,
            model: metadata.model,
            appVersion: metadata.appVersion
        ).intoTags()
        combined.append(contentsOf: tags)
        return combined
    }

    private func multiAgentSpawnTags(
        forkMode: String,
        multiAgentVersion: String
    ) -> [(String, String)] {
        var tags = [
            ("fork_mode", forkMode),
            ("multi_agent_version", multiAgentVersion),
        ]
        if let productSku = metadata.productSku {
            tags.append(("product_sku", productSku))
        }
        return tags
    }
}

func sessionSourceTelemetryLabel(_ source: SessionSource) -> String {
    switch source {
    case .cli: return "cli"
    case .vsCode: return "vscode"
    case .exec: return "exec"
    case .mcp: return "mcp"
    case .custom(let value): return value
    case .internal: return "internal"
    case .subAgent: return "subagent"
    case .unknown: return "unknown"
    }
}

func parseEstimatedMicrousd(_ estimatedUsd: String) -> Int64? {
    let parts = estimatedUsd.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
    let dollarsPart = String(parts.first ?? "")
    let fractional = parts.count > 1 ? Array(parts[1].utf8) : []
    let precision = 6
    guard let dollars = UInt64(dollarsPart), fractional.allSatisfy({ $0 >= 48 && $0 <= 57 }) else {
        return nil
    }
    var fractionalMicro: UInt64 = 0
    for digit in fractional.prefix(precision) {
        fractionalMicro = fractionalMicro * 10 + UInt64(digit - 48)
    }
    let pad = precision - min(precision, fractional.count)
    if pad > 0 {
        fractionalMicro *= pow10u64(pad)
    }
    let roundUp = fractional.count > precision && fractional[precision] >= 53
    guard
        dollars <= UInt64.max / 1_000_000,
        fractionalMicro <= UInt64.max - dollars * 1_000_000
    else {
        return nil
    }
    let total = dollars * 1_000_000 + fractionalMicro + (roundUp ? 1 : 0)
    return Int64(exactly: total)
}

private func pow10u64(_ exponent: Int) -> UInt64 {
    var value: UInt64 = 1
    for _ in 0..<exponent {
        value *= 10
    }
    return value
}
