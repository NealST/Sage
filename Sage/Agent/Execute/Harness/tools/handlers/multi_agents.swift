//
//  multi_agents.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/handlers/multi_agents.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  ID parsing and collab status mapping are faithful. Handler bodies wait
//  on AgentControl / Session.
//

import CodexCore
import CodexProtocol

let MULTI_AGENT_TOOL_SEARCH_SOURCE_NAME = "Multi-agent tools"
let MULTI_AGENT_TOOL_SEARCH_SOURCE_DESCRIPTION = "Spawn and manage sub-agents."

func parseAgentIdTarget(_ target: String) throws -> ThreadId {
    do {
        return try ThreadId.fromString(target)
    } catch {
        throw FunctionCallError.respondToModel("invalid agent id \(target): \(error)")
    }
}

func parseAgentIdTargets(_ targets: [String]) throws -> [ThreadId] {
    if targets.isEmpty {
        throw FunctionCallError.respondToModel("agent ids must be non-empty")
    }
    return try targets.map { try parseAgentIdTarget($0) }
}

func collabToolCallStatus(
    _ status: AgentStatus,
    receiverThreadId: ThreadId?
) -> CollabAgentToolCallStatus {
    switch status {
    case .errored, .notFound:
        return .failed
    default:
        return receiverThreadId == nil ? .failed : .completed
    }
}

func multiAgentToolSearchInfo(searchText: String, spec: ToolSpec) -> ToolSearchInfo? {
    ToolSearchInfo(
        description: searchText,
        keywords: [spec.name()],
        source: ToolSearchSourceInfo(
            name: MULTI_AGENT_TOOL_SEARCH_SOURCE_NAME,
            description: MULTI_AGENT_TOOL_SEARCH_SOURCE_DESCRIPTION
        )
    )
}
