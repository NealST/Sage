//
//  session_mcp.swift
//  Sage
//
//  Port of codex-rs/core/src/session/mcp.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Elicitation review and plugin-install telemetry stay out. This file is
//  the session binding: connect enabled servers, list the model-visible
//  catalog, run one prepared tool call, and wait for an MCP elicitation.
//  `requestMcpServerElicitation` pauses the session until `resolveElicitation`
//  resumes that waiter. A missing waiter falls through to the MCP runtime.
//

import CodexCore
import CodexProtocol
import Foundation

extension Session {
    func ensureMcpConnected() async {
        await services.ensureMcpConnected?()
    }

    func listMcpTools() -> [String] {
        if !services.mcpVisibleTools.isEmpty {
            return services.mcpVisibleTools.map(\.name)
        }
        return services.modelVisibleMcpToolNames
    }

    func callMcpTool(
        server: String,
        toolName: String,
        arguments: String,
        enabled: Bool = true,
        inputModalities: [InputModality] = defaultInputModalities()
    ) async -> HandledMcpToolCall {
        let prepared = services.mcpVisibleTools.contains { tool in
            tool.name == toolName && (tool.serverName == server || tool.serverName == nil)
        } ? PreparedMcpToolCall(serverName: server, toolName: toolName, enabled: enabled) : nil
        let transport = services.mcpToolTransport ?? { _ in
            throw McpToolCallFailure("MCP transport is not attached")
        }
        return await handleMcpToolCall(
            server: server,
            toolName: toolName,
            arguments: arguments,
            prepared: prepared,
            inputModalities: inputModalities,
            transport: transport
        )
    }

    /// rust `Session::request_mcp_server_elicitation`.
    /// Auto-deny accepts an empty form and does not emit a request.
    /// Without an active turn the request is still emitted and the waiter
    /// is already cancelled. A replacement request cancels the previous one.
    func requestMcpServerElicitation(
        turnContext: TurnContext,
        serverName: String,
        requestId: RequestId,
        request: ElicitationRequest
    ) async -> McpServerElicitationOutcome {
        if services.mcpRuntime.elicitationsAutoDeny {
            return McpServerElicitationOutcome(
                response: ElicitationResponse(action: .accept, content: .object([:])),
                sent: false
            )
        }
        let registration = services.elicitations.register()
        let response: ElicitationResponse? = await withCheckedContinuation { continuation in
            let decision = ElicitationDecision(continuation)
            if let turn = activeTurn {
                let previous = turn.turnState.insertPendingElicitation(
                    serverName: serverName, requestId: requestId, decision: decision)
                previous?.resume(nil)
            }
            sendEvent(
                turnContext,
                .elicitationRequest(
                    ElicitationRequestEvent(
                        turnId: turnContext.subId,
                        serverName: serverName,
                        id: requestId,
                        request: request
                    )
                )
            )
            if activeTurn == nil {
                decision.resume(nil)
            }
        }
        withExtendedLifetime(registration) {}
        return McpServerElicitationOutcome(response: response, sent: true)
    }

    /// rust `Session::resolve_elicitation`. A live waiter wins. Otherwise the
    /// MCP runtime fallback receives the response. A missing fallback is ignored.
    func resolveElicitation(
        serverName: String,
        id: RequestId,
        response: ElicitationResponse
    ) async {
        if let decision = activeTurn?.turnState.removePendingElicitation(
            serverName: serverName, requestId: id) {
            decision.resume(response)
            return
        }
        guard let fallback = services.mcpRuntime.resolveElicitationFallback else { return }
        do {
            try await fallback(serverName, id, response)
        } catch {
            return
        }
    }
}

struct McpServerElicitationOutcome: Equatable, Sendable {
    var response: ElicitationResponse?
    var sent: Bool
}

func submittedElicitationResponse(
    decision: ElicitationAction,
    content: CodexProtocol.JSONValue?,
    meta: CodexProtocol.JSONValue?
) -> ElicitationResponse {
    let accepted: CodexProtocol.JSONValue?
    switch decision {
    case .accept:
        accepted = content ?? .object([:])
    case .decline, .cancel:
        accepted = nil
    }
    return ElicitationResponse(action: decision, content: accepted, meta: meta)
}
