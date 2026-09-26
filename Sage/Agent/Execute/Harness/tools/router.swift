//
//  router.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/router.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Session/StepContext wait for Phase 5. The router maps model-visible
//  calls onto the registry and builds a Session-free ToolInvocation.
//

import CodexProtocol

struct ToolCall: Equatable, Sendable {
    var toolName: ToolName
    var callId: String
    var payload: ToolPayload
    var encryptedFunctionArgs: [String]?

    func directSource() -> ToolCallSource {
        if toolName.namespace == "collaboration",
           ["spawn_agent", "send_message", "followup_task"].contains(toolName.name),
           encryptedFunctionArgs?.isEmpty == true {
            return .directPlaintextMessage
        }
        return .direct
    }
}

func toolLogPayload(_ payload: ToolPayload, source: ToolCallSource) -> String {
    if source == .directPlaintextMessage {
        return "[plaintext arguments]"
    }
    return payload.logPayload()
}

struct ToolRouter {
    var registry: HarnessToolRegistry
    var modelVisibleSpecs: [ToolSpec]
    var toolMode: ToolMode
    var canManageChildren: Bool

    func buildInvocation(
        _ call: ToolCall,
        turnId: String = "",
        threadId: ThreadId? = nil,
        modeKind: ModeKind = .default
    ) -> ToolInvocation {
        ToolInvocation(
            callId: call.callId,
            toolName: call.toolName,
            source: call.directSource(),
            payload: call.payload,
            turnId: turnId,
            threadId: threadId,
            modeKind: modeKind
        )
    }

    func dispatch(_ call: ToolCall) async throws -> AnyToolResult {
        try await registry.dispatch(buildInvocation(call))
    }
}
