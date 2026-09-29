//
//  mcp_runner.swift
//  CodexHooks
//
//  Port of codex-rs/hooks/src/engine/mcp_runner.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Template expansion uses NSRegularExpression for `${field.nested}`.
//  MCP execution still goes through HookMcpExecutor.
//

import CodexProtocol
import Foundation

public func runMcpTool(
    executor: any HookMcpExecutor,
    call: HookMcpCall
) async throws -> String {
    try await executor.execute(call)
}

func runMcpTool(
    executor: any HookMcpExecutor,
    handler: ConfiguredHandler,
    server: String,
    tool: String,
    argumentTemplate: [String: JSONValue],
    hookEventJSON: String,
    metadata: [String: JSONValue]?
) async -> HandlerRunResult {
    let startedAt = Int64(Date().timeIntervalSince1970)
    let started = ContinuousClock.now
    do {
        guard let data = hookEventJSON.data(using: .utf8) else {
            throw CodexErr.fatal("failed to parse hook event input")
        }
        let hookEvent = try JSONDecoder().decode(JSONValue.self, from: data)
        let input = try expandMcpArgumentTemplate(argumentTemplate, hookEvent: hookEvent)
        let environmentId: String?
        var callMetadata: [String: JSONValue]?
        switch handler.sourcePath {
        case .local:
            environmentId = nil
            callMetadata = nil
        case .executorScoped(_, let envId, let mcpEnvironmentId, let mcpMetadata, _, _):
            environmentId = mcpEnvironmentId ?? envId
            callMetadata = mcpMetadata
        }
        if let metadata {
            var merged = callMetadata ?? [:]
            for (key, value) in metadata {
                merged[key] = value
            }
            callMetadata = merged
        }
        let output = try await executor.execute(
            HookMcpCall(
                server: server,
                tool: tool,
                environmentId: environmentId,
                metadata: callMetadata,
                input: input,
                timeout: TimeInterval(handler.timeoutSec)
            )
        )
        return finishMcpRun(
            startedAt: startedAt, started: started,
            exitCode: 0, stdout: output, error: nil
        )
    } catch {
        return finishMcpRun(
            startedAt: startedAt, started: started,
            exitCode: nil, stdout: "", error: String(describing: error)
        )
    }
}

func expandMcpArgumentTemplate(
    _ argumentTemplate: [String: JSONValue],
    hookEvent: JSONValue
) throws -> [String: JSONValue] {
    var resolved: [String: JSONValue] = [:]
    for (key, value) in argumentTemplate {
        resolved[key] = try resolveMcpValue(value, hookEvent: hookEvent)
    }
    return resolved
}

private func finishMcpRun(
    startedAt: Int64,
    started: ContinuousClock.Instant,
    exitCode: Int32?,
    stdout: String,
    error: String?
) -> HandlerRunResult {
    let duration = started.duration(to: .now)
    let durationMs = Int64(duration.components.seconds * 1000)
        + Int64(duration.components.attoseconds / 1_000_000_000_000_000)
    return HandlerRunResult(
        startedAt: startedAt,
        completedAt: Int64(Date().timeIntervalSince1970),
        durationMs: max(durationMs, 0),
        exitCode: exitCode,
        stdout: stdout,
        stderr: "",
        error: error
    )
}

private func resolveMcpValue(_ value: JSONValue, hookEvent: JSONValue) throws -> JSONValue {
    switch value {
    case .object(let object):
        return .object(try expandMcpArgumentTemplate(object, hookEvent: hookEvent))
    case .array(let items):
        return .array(try items.map { try resolveMcpValue($0, hookEvent: hookEvent) })
    case .string(let text):
        return try resolveMcpString(text, hookEvent: hookEvent)
    default:
        return value
    }
}

private func resolveMcpString(_ text: String, hookEvent: JSONValue) throws -> JSONValue {
    let regex = try NSRegularExpression(pattern: #"\$\{([^{}]+)\}"#)
    let ns = text as NSString
    let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
    if matches.isEmpty {
        return .string(text)
    }
    if matches.count == 1,
       matches[0].range.location == 0,
       matches[0].range.length == ns.length {
        let path = ns.substring(with: matches[0].range(at: 1))
        guard let value = resolveMcpPath(hookEvent, path) else {
            throw CodexErr.fatal("hook input placeholder `${\(path)}` was not found")
        }
        return value
    }
    var resolved = ""
    var previous = 0
    for match in matches {
        let range = match.range
        resolved += ns.substring(with: NSRange(location: previous, length: range.location - previous))
        let path = ns.substring(with: match.range(at: 1))
        guard let value = resolveMcpPath(hookEvent, path) else {
            throw CodexErr.fatal("hook input placeholder `${\(path)}` was not found")
        }
        if case .string(let text) = value {
            resolved += text
        } else {
            resolved += value.encodedString()
        }
        previous = range.location + range.length
    }
    resolved += ns.substring(from: previous)
    return .string(resolved)
}

private func resolveMcpPath(_ hookEvent: JSONValue, _ path: String) -> JSONValue? {
    path.split(separator: ".").reduce(hookEvent as JSONValue?) { current, field in
        current?.objectValue?[String(field)]
    }
}
