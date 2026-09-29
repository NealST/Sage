//
//  schema_loader.swift
//  CodexHooks
//
//  Port of codex-rs/hooks/src/engine/schema_loader.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Upstream `include_str!` maps to `Bundle.module` copies of
//  `schema/generated/*.schema.json` (same fixtures as rust). Invalid
//  fixtures still trap at load, like the rust panic.
//

import CodexProtocol
import Foundation

public struct GeneratedHookSchemas: Equatable, Sendable {
    public var postToolUseCommandInput: JSONValue
    public var postToolUseCommandOutput: JSONValue
    public var permissionRequestCommandInput: JSONValue
    public var permissionRequestCommandOutput: JSONValue
    public var postCompactCommandInput: JSONValue
    public var postCompactCommandOutput: JSONValue
    public var preToolUseCommandInput: JSONValue
    public var preToolUseCommandOutput: JSONValue
    public var preCompactCommandInput: JSONValue
    public var preCompactCommandOutput: JSONValue
    public var sessionStartCommandInput: JSONValue
    public var sessionStartCommandOutput: JSONValue
    public var sessionEndCommandInput: JSONValue
    public var subagentStartCommandInput: JSONValue
    public var subagentStartCommandOutput: JSONValue
    public var subagentStopCommandInput: JSONValue
    public var subagentStopCommandOutput: JSONValue
    public var userPromptSubmitCommandInput: JSONValue
    public var userPromptSubmitCommandOutput: JSONValue
    public var stopCommandInput: JSONValue
    public var stopCommandOutput: JSONValue
    public var interruptCommandInput: JSONValue
    public var interruptCommandOutput: JSONValue
}

private enum GeneratedHookSchemasCache {
    static let schemas = loadGeneratedHookSchemas()
}

public func generatedHookSchemas() -> GeneratedHookSchemas {
    GeneratedHookSchemasCache.schemas
}

func parseJSONSchema(_ name: String, _ schema: String) -> JSONValue {
    guard let data = schema.data(using: .utf8),
          let value = try? JSONDecoder().decode(JSONValue.self, from: data)
    else {
        preconditionFailure("invalid generated hooks schema \(name)")
    }
    return value
}

private func loadGeneratedHookSchemas() -> GeneratedHookSchemas {
    GeneratedHookSchemas(
        postToolUseCommandInput: loadHookSchema("post-tool-use.command.input"),
        postToolUseCommandOutput: loadHookSchema("post-tool-use.command.output"),
        permissionRequestCommandInput: loadHookSchema("permission-request.command.input"),
        permissionRequestCommandOutput: loadHookSchema("permission-request.command.output"),
        postCompactCommandInput: loadHookSchema("post-compact.command.input"),
        postCompactCommandOutput: loadHookSchema("post-compact.command.output"),
        preToolUseCommandInput: loadHookSchema("pre-tool-use.command.input"),
        preToolUseCommandOutput: loadHookSchema("pre-tool-use.command.output"),
        preCompactCommandInput: loadHookSchema("pre-compact.command.input"),
        preCompactCommandOutput: loadHookSchema("pre-compact.command.output"),
        sessionStartCommandInput: loadHookSchema("session-start.command.input"),
        sessionStartCommandOutput: loadHookSchema("session-start.command.output"),
        sessionEndCommandInput: loadHookSchema("session-end.command.input"),
        subagentStartCommandInput: loadHookSchema("subagent-start.command.input"),
        subagentStartCommandOutput: loadHookSchema("subagent-start.command.output"),
        subagentStopCommandInput: loadHookSchema("subagent-stop.command.input"),
        subagentStopCommandOutput: loadHookSchema("subagent-stop.command.output"),
        userPromptSubmitCommandInput: loadHookSchema("user-prompt-submit.command.input"),
        userPromptSubmitCommandOutput: loadHookSchema("user-prompt-submit.command.output"),
        stopCommandInput: loadHookSchema("stop.command.input"),
        stopCommandOutput: loadHookSchema("stop.command.output"),
        interruptCommandInput: loadHookSchema("interrupt.command.input"),
        interruptCommandOutput: loadHookSchema("interrupt.command.output")
    )
}

private func loadHookSchema(_ name: String) -> JSONValue {
    guard let url = hookSchemaResourceURL(name) else {
        preconditionFailure("missing generated hooks schema \(name)")
    }
    guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
        preconditionFailure("failed to read generated hooks schema \(name)")
    }
    return parseJSONSchema(name, contents)
}

private func hookSchemaResourceURL(_ name: String) -> URL? {
    let stem = "\(name).schema"
    let file = "\(name).schema.json"
    let subdirectories = ["generated", "schema/generated", nil]
    for subdirectory in subdirectories {
        if let url = Bundle.module.url(
            forResource: stem,
            withExtension: "json",
            subdirectory: subdirectory
        ) {
            return url
        }
        if let url = Bundle.module.url(
            forResource: file,
            withExtension: nil,
            subdirectory: subdirectory
        ) {
            return url
        }
        if let url = Bundle.module.url(
            forResource: name,
            withExtension: "schema.json",
            subdirectory: subdirectory
        ) {
            return url
        }
    }
    if let root = Bundle.module.resourceURL {
        let candidates = [
            root.appendingPathComponent("generated").appendingPathComponent(file),
            root.appendingPathComponent("schema/generated").appendingPathComponent(file),
            root.appendingPathComponent(file),
        ]
        if let url = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            return url
        }
    }
    return nil
}
