//
//  runtime_metrics.swift
//  CodexOtel
//
//  Port of codex-rs/otel/src/metrics/runtime_metrics.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Totals / summary types are faithful. Snapshot aggregation reads
//  in-memory MetricObservation instead of SDK ResourceMetrics.
//

public struct RuntimeMetricTotals: Equatable, Sendable {
    public var count: UInt64
    public var durationMs: UInt64

    public init(count: UInt64 = 0, durationMs: UInt64 = 0) {
        self.count = count
        self.durationMs = durationMs
    }

    public var isEmpty: Bool { count == 0 && durationMs == 0 }

    public mutating func merge(_ other: RuntimeMetricTotals) {
        count = count &+ other.count
        durationMs = durationMs &+ other.durationMs
    }
}

public struct RuntimeMetricsSummary: Equatable, Sendable {
    public var toolCalls: RuntimeMetricTotals
    public var apiCalls: RuntimeMetricTotals
    public var streamingEvents: RuntimeMetricTotals
    public var websocketCalls: RuntimeMetricTotals
    public var websocketEvents: RuntimeMetricTotals
    public var responsesApiOverheadMs: UInt64
    public var responsesApiInferenceTimeMs: UInt64
    public var responsesApiEngineIapiTtftMs: UInt64
    public var responsesApiEngineServiceTtftMs: UInt64
    public var responsesApiEngineIapiTbtMs: Double
    public var responsesApiEngineServiceTbtMs: Double
    public var turnTtftMs: UInt64
    public var turnTtfmMs: UInt64

    public init() {
        toolCalls = RuntimeMetricTotals()
        apiCalls = RuntimeMetricTotals()
        streamingEvents = RuntimeMetricTotals()
        websocketCalls = RuntimeMetricTotals()
        websocketEvents = RuntimeMetricTotals()
        responsesApiOverheadMs = 0
        responsesApiInferenceTimeMs = 0
        responsesApiEngineIapiTtftMs = 0
        responsesApiEngineServiceTtftMs = 0
        responsesApiEngineIapiTbtMs = 0
        responsesApiEngineServiceTbtMs = 0
        turnTtftMs = 0
        turnTtfmMs = 0
    }

    public var isEmpty: Bool {
        toolCalls.isEmpty
            && apiCalls.isEmpty
            && streamingEvents.isEmpty
            && websocketCalls.isEmpty
            && websocketEvents.isEmpty
            && responsesApiOverheadMs == 0
            && responsesApiInferenceTimeMs == 0
            && responsesApiEngineIapiTtftMs == 0
            && responsesApiEngineServiceTtftMs == 0
            && responsesApiEngineIapiTbtMs == 0
            && responsesApiEngineServiceTbtMs == 0
            && turnTtftMs == 0
            && turnTtfmMs == 0
    }

    public mutating func merge(_ other: RuntimeMetricsSummary) {
        toolCalls.merge(other.toolCalls)
        apiCalls.merge(other.apiCalls)
        streamingEvents.merge(other.streamingEvents)
        websocketCalls.merge(other.websocketCalls)
        websocketEvents.merge(other.websocketEvents)
        responsesApiOverheadMs &+= other.responsesApiOverheadMs
        responsesApiInferenceTimeMs &+= other.responsesApiInferenceTimeMs
        responsesApiEngineIapiTtftMs &+= other.responsesApiEngineIapiTtftMs
        responsesApiEngineServiceTtftMs &+= other.responsesApiEngineServiceTtftMs
        responsesApiEngineIapiTbtMs += other.responsesApiEngineIapiTbtMs
        responsesApiEngineServiceTbtMs += other.responsesApiEngineServiceTbtMs
        turnTtftMs &+= other.turnTtftMs
        turnTtfmMs &+= other.turnTtfmMs
    }

    public static func fromObservations(_ observations: [MetricObservation]) -> RuntimeMetricsSummary {
        var summary = RuntimeMetricsSummary()
        for observation in observations {
            switch observation.name {
            case TOOL_CALL_COUNT_METRIC:
                summary.toolCalls.count &+= UInt64(max(0, observation.value))
            case TOOL_CALL_DURATION_METRIC:
                summary.toolCalls.durationMs &+= UInt64(max(0, observation.value))
            case API_CALL_COUNT_METRIC:
                summary.apiCalls.count &+= UInt64(max(0, observation.value))
            case API_CALL_DURATION_METRIC:
                summary.apiCalls.durationMs &+= UInt64(max(0, observation.value))
            case SSE_EVENT_COUNT_METRIC:
                summary.streamingEvents.count &+= UInt64(max(0, observation.value))
            case SSE_EVENT_DURATION_METRIC:
                summary.streamingEvents.durationMs &+= UInt64(max(0, observation.value))
            case WEBSOCKET_REQUEST_COUNT_METRIC:
                summary.websocketCalls.count &+= UInt64(max(0, observation.value))
            case WEBSOCKET_REQUEST_DURATION_METRIC:
                summary.websocketCalls.durationMs &+= UInt64(max(0, observation.value))
            case WEBSOCKET_EVENT_COUNT_METRIC:
                summary.websocketEvents.count &+= UInt64(max(0, observation.value))
            case WEBSOCKET_EVENT_DURATION_METRIC:
                summary.websocketEvents.durationMs &+= UInt64(max(0, observation.value))
            case RESPONSES_API_OVERHEAD_DURATION_METRIC:
                summary.responsesApiOverheadMs &+= UInt64(max(0, observation.value))
            case RESPONSES_API_INFERENCE_TIME_DURATION_METRIC:
                summary.responsesApiInferenceTimeMs &+= UInt64(max(0, observation.value))
            case RESPONSES_API_ENGINE_IAPI_TTFT_DURATION_METRIC:
                summary.responsesApiEngineIapiTtftMs &+= UInt64(max(0, observation.value))
            case RESPONSES_API_ENGINE_SERVICE_TTFT_DURATION_METRIC:
                summary.responsesApiEngineServiceTtftMs &+= UInt64(max(0, observation.value))
            case RESPONSES_API_ENGINE_IAPI_TBT_DURATION_METRIC:
                summary.responsesApiEngineIapiTbtMs += observation.value
            case RESPONSES_API_ENGINE_SERVICE_TBT_DURATION_METRIC:
                summary.responsesApiEngineServiceTbtMs += observation.value
            case TURN_TTFT_DURATION_METRIC:
                summary.turnTtftMs &+= UInt64(max(0, observation.value))
            case TURN_TTFM_DURATION_METRIC:
                summary.turnTtfmMs &+= UInt64(max(0, observation.value))
            default:
                break
            }
        }
        return summary
    }
}
