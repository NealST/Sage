//
//  mcp_tool_call.swift
//  CodexCore
//
//  Port of codex-rs/core/src/mcp_tool_call.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Argument parsing, unavailable and blocked calls, transport errors, and
//  modality sanitizing. Approval, elicitation, and OpenAI file rewrite stay
//  on the session. The app transport is MCPStdioClient via CapabilityStore.
//

import CodexProtocol
import Foundation

public struct McpToolCallRequest: Equatable, Sendable {
    public var serverName: String
    public var toolName: String
    public var argumentsJSON: String

    public init(serverName: String, toolName: String, argumentsJSON: String) {
        self.serverName = serverName
        self.toolName = toolName
        self.argumentsJSON = argumentsJSON
    }
}

public struct McpToolCallResult: Equatable, Sendable {
    public var content: String
    public var isError: Bool

    public init(content: String, isError: Bool = false) {
        self.content = content
        self.isError = isError
    }
}

public struct PreparedMcpToolCall: Equatable, Sendable {
    public var serverName: String
    public var toolName: String
    public var enabled: Bool

    public init(serverName: String, toolName: String, enabled: Bool = true) {
        self.serverName = serverName
        self.toolName = toolName
        self.enabled = enabled
    }
}

public struct HandledMcpToolCall: Equatable, Sendable {
    public var result: CallToolResult
    public var toolInputJSON: String

    public init(result: CallToolResult, toolInputJSON: String) {
        self.result = result
        self.toolInputJSON = toolInputJSON
    }
}

public struct McpToolCallFailure: Error, Equatable, CustomStringConvertible, Sendable {
    public var message: String

    public init(_ message: String) {
        self.message = message
    }

    public var description: String { message }
}

public func mcpTextResult(_ text: String, isError: Bool = false) -> CallToolResult {
    CallToolResult(
        content: [.object(["type": .string("text"), "text": .string(text)])],
        structuredContent: nil,
        isError: isError ? true : nil,
        meta: nil
    )
}

/// Decode a raw `tools/call` body when the transport returns one. Other text
/// stays a single text block.
public func callToolResult(fromTransportText text: String, isError: Bool = false) -> CallToolResult {
    if !isError,
       let data = text.data(using: .utf8),
       let decoded = try? JSONDecoder().decode(CallToolResult.self, from: data),
       !decoded.content.isEmpty {
        return decoded
    }
    return mcpTextResult(text, isError: isError)
}

public func mcpToolResultText(_ result: CallToolResult) -> String {
    result.content.compactMap { block in
        guard case .object(let fields) = block else { return nil }
        guard case .string(let text) = fields["text"] else { return nil }
        return text
    }.joined(separator: "\n")
}

/// Codex `handle_mcp_tool_call` through the approved transport call.
/// A missing preparation or a disabled app tool never reaches `transport`.
public func handleMcpToolCall(
    server: String,
    toolName: String,
    arguments: String,
    prepared: PreparedMcpToolCall?,
    inputModalities: [InputModality] = defaultInputModalities(),
    transport: @escaping @Sendable (McpToolCallRequest) async throws -> CallToolResult
) async -> HandledMcpToolCall {
    let toolInputJSON: String
    switch parseMcpArguments(arguments) {
    case .invalid(let message):
        return HandledMcpToolCall(
            result: .fromErrorText(message),
            toolInputJSON: "{}"
        )
    case .json(let json):
        toolInputJSON = json
    }

    guard let prepared else {
        return HandledMcpToolCall(
            result: .fromErrorText(
                "MCP tool `\(server)/\(toolName)` is not available to the model"
            ),
            toolInputJSON: toolInputJSON
        )
    }
    if !prepared.enabled {
        return HandledMcpToolCall(
            result: .fromErrorText("MCP tool call blocked by app configuration"),
            toolInputJSON: toolInputJSON
        )
    }

    let request = McpToolCallRequest(
        serverName: prepared.serverName,
        toolName: prepared.toolName,
        argumentsJSON: toolInputJSON
    )
    let result: CallToolResult
    do {
        result = try await transport(request)
    } catch {
        let message = (error as? McpToolCallFailure)?.message ?? error.localizedDescription
        return HandledMcpToolCall(
            result: .fromErrorText("tool call error: \(message)"),
            toolInputJSON: toolInputJSON
        )
    }
    return HandledMcpToolCall(
        result: sanitizeMcpToolResultForModel(inputModalities, result: result),
        toolInputJSON: toolInputJSON
    )
}

enum McpArgumentParse {
    case json(String)
    case invalid(String)
}

func parseMcpArguments(_ arguments: String) -> McpArgumentParse {
    let trimmed = arguments.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
        return .json("{}")
    }
    guard let data = trimmed.data(using: .utf8) else {
        return .invalid("err: arguments were not valid UTF-8")
    }
    do {
        _ = try JSONDecoder().decode(JSONValue.self, from: data)
        return .json(trimmed)
    } catch {
        return .invalid("err: \(error.localizedDescription)")
    }
}

func sanitizeMcpToolResultForModel(
    _ inputModalities: [InputModality],
    result: CallToolResult
) -> CallToolResult {
    let supportsImage = inputModalities.contains(.image)
    let supportsAudio = inputModalities.contains(.audio)
    if supportsImage && supportsAudio {
        return result
    }
    var copy = result
    copy.content = result.content.map { block in
        guard case .object(let fields) = block else { return block }
        guard case .string(let contentType) = fields["type"] else { return block }
        if contentType == "image", !supportsImage {
            return .object([
                "type": .string("text"),
                "text": .string("<image content omitted because you do not support image input>"),
            ])
        }
        if contentType == "audio", !supportsAudio {
            return .object([
                "type": .string("text"),
                "text": .string("<audio content omitted because you do not support audio input>"),
            ])
        }
        return block
    }
    return copy
}
