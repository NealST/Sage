//
//  names.swift
//  CodexOtel
//
//  Port of codex-rs/otel/src/metrics/names.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//

public let TOOL_CALL_COUNT_METRIC = "codex.tool.call"
public let TOOL_CALL_DURATION_METRIC = "codex.tool.call.duration_ms"
public let TOOL_CALL_UNIFIED_EXEC_METRIC = "codex.tool.unified_exec"
public let MULTI_AGENT_SPAWN_FAILURE_METRIC = "codex.multi_agent.spawn.failure"
public let MULTI_AGENT_SPAWN_PHASE_DURATION_METRIC = "codex.multi_agent.spawn.phase.duration_ms"
public let ARTIFACT_OPERATION_STARTED_METRIC = "codex.artifact.operation.started"
public let ARTIFACT_OPERATION_EXPECTED_OUTPUT_COUNT_METRIC =
    "codex.artifact.operation.expected_output_count"
public let PROCESS_START_METRIC = "codex.process.start"
public let EXEC_SERVER_CLIENT_REQUEST_COUNT_METRIC = "exec_server_client_requests_total"
public let API_CALL_COUNT_METRIC = "codex.api_request"
public let API_CALL_DURATION_METRIC = "codex.api_request.duration_ms"
public let SSE_EVENT_COUNT_METRIC = "codex.sse_event"
public let SSE_EVENT_DURATION_METRIC = "codex.sse_event.duration_ms"
public let WEBSOCKET_REQUEST_COUNT_METRIC = "codex.websocket.request"
public let WEBSOCKET_CONTINUATION_COUNT_METRIC = "codex.websocket.continuation"
public let WEBSOCKET_REQUEST_DURATION_METRIC = "codex.websocket.request.duration_ms"
public let WEBSOCKET_EVENT_COUNT_METRIC = "codex.websocket.event"
public let WEBSOCKET_EVENT_DURATION_METRIC = "codex.websocket.event.duration_ms"
public let RESPONSES_API_OVERHEAD_DURATION_METRIC = "codex.responses_api_overhead.duration_ms"
public let RESPONSES_API_INFERENCE_TIME_DURATION_METRIC =
    "codex.responses_api_inference_time.duration_ms"
public let RESPONSES_API_ENGINE_IAPI_TTFT_DURATION_METRIC =
    "codex.responses_api_engine_iapi_ttft.duration_ms"
public let RESPONSES_API_ENGINE_SERVICE_TTFT_DURATION_METRIC =
    "codex.responses_api_engine_service_ttft.duration_ms"
public let RESPONSES_API_ENGINE_IAPI_TBT_DURATION_METRIC =
    "codex.responses_api_engine_iapi_tbt.duration_ms"
public let RESPONSES_API_ENGINE_SERVICE_TBT_DURATION_METRIC =
    "codex.responses_api_engine_service_tbt.duration_ms"
public let TURN_E2E_DURATION_METRIC = "codex.turn.e2e_duration_ms"
public let TURN_TTFT_DURATION_METRIC = "codex.turn.ttft.duration_ms"
public let TURN_TTFM_DURATION_METRIC = "codex.turn.ttfm.duration_ms"
public let TURN_NETWORK_PROXY_METRIC = "codex.turn.network_proxy"
public let TURN_MEMORY_METRIC = "codex.turn.memory"
public let TURN_TOOL_CALL_METRIC = "codex.turn.tool.call"
public let TURN_TOKEN_USAGE_METRIC = "codex.turn.token_usage"
public let TURN_COST_MICROUSD_METRIC = "codex.turn.cost_microusd"
public let TURN_UNIFIED_EXEC_RUNNING_PROCESSES_METRIC =
    "codex.turn.unified_exec.running_processes"
public let GUARDIAN_REVIEW_COUNT_METRIC = "codex.guardian.review"
public let GUARDIAN_REVIEW_DURATION_METRIC = "codex.guardian.review.duration_ms"
public let GUARDIAN_REVIEW_TTFT_DURATION_METRIC = "codex.guardian.review.ttft.duration_ms"
public let GUARDIAN_REVIEW_TOKEN_USAGE_METRIC = "codex.guardian.review.token_usage"
public let GOAL_CREATED_METRIC = "codex.goal.created"
public let GOAL_RESUMED_METRIC = "codex.goal.resumed"
public let GOAL_COMPLETED_METRIC = "codex.goal.completed"
public let GOAL_BUDGET_LIMITED_METRIC = "codex.goal.budget_limited"
public let GOAL_USAGE_LIMITED_METRIC = "codex.goal.usage_limited"
public let GOAL_BLOCKED_METRIC = "codex.goal.blocked"
public let GOAL_TOKEN_COUNT_METRIC = "codex.goal.token_count"
public let GOAL_DURATION_SECONDS_METRIC = "codex.goal.duration_s"
public let PLUGIN_INSTALL_ELICITATION_SENT_METRIC = "codex.plugins.install_elicitation.sent"
public let PLUGIN_INSTALL_SUGGESTION_METRIC = "codex.plugins.install_suggestion"
public let CURATED_PLUGINS_STARTUP_SYNC_METRIC = "codex.plugins.startup_sync"
public let CURATED_PLUGINS_STARTUP_SYNC_FINAL_METRIC = "codex.plugins.startup_sync.final"
public let HOOK_RUN_METRIC = "codex.hooks.run"
public let HOOK_RUN_DURATION_METRIC = "codex.hooks.run.duration_ms"
public let STARTUP_PHASE_DURATION_METRIC = "codex.startup.phase.duration_ms"
public let STARTUP_PREWARM_DURATION_METRIC = "codex.startup_prewarm.duration_ms"
public let STARTUP_PREWARM_AGE_AT_FIRST_TURN_METRIC =
    "codex.startup_prewarm.age_at_first_turn_ms"
public let THREAD_STARTED_METRIC = "codex.thread.started"
public let THREAD_SKILLS_ENABLED_TOTAL_METRIC = "codex.thread.skills.enabled_total"
public let THREAD_SKILLS_KEPT_TOTAL_METRIC = "codex.thread.skills.kept_total"
public let THREAD_SKILLS_DESCRIPTION_TRUNCATED_CHARS_METRIC =
    "codex.thread.skills.description_truncated_chars"
public let THREAD_SKILLS_TRUNCATED_METRIC = "codex.thread.skills.truncated"
public let THREAD_TOOLS_NAMESPACES_TOTAL_METRIC = "codex.thread.tools.namespaces_total"
public let THREAD_TOOLS_FRAGMENT_BYTES_METRIC = "codex.thread.tools.fragment_bytes"

public let CONTEXT_FRAGMENT_BYTES_BUCKETS: [Double] = [
    256, 512, 1_024, 2_048, 4_096, 8_192, 16_384,
]
