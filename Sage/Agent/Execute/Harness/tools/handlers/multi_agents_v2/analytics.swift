//
//  analytics.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/handlers/multi_agents_v2/analytics.rs
//  (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Analytics emit waits on SessionTelemetry.
//

import CodexCore
import CodexProtocol

func recordMultiAgentV2ToolCall(toolName: String, status: String) {
    _ = toolName
    _ = status
}
