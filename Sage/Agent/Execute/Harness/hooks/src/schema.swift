//
//  schema.swift
//  CodexHooks
//
//  Port of codex-rs/hooks/src/schema.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Wire input/output structs used on hook stdin/stdout are ported.
//  `write_schema_fixtures` and schemars generation wait on embedded
//  fixtures / a Swift JSON Schema crate.
//

import CodexProtocol
import Foundation

public struct NullableString: Equatable, Sendable {
    public var value: String?

    public init(_ value: String? = nil) {
        self.value = value
    }

    public static func fromPath(_ path: String?) -> NullableString {
        NullableString(path)
    }

    public static func fromString(_ value: String?) -> NullableString {
        NullableString(value)
    }
}

public struct SubagentCommandInputFields: Equatable, Sendable {
    public var agentId: String?
    public var agentType: String?

    public init(agentId: String? = nil, agentType: String? = nil) {
        self.agentId = agentId
        self.agentType = agentType
    }

    public init(_ context: SubagentHookContext?) {
        self.agentId = context?.agentId
        self.agentType = context?.agentType
    }
}

public struct HookUniversalOutputWire: Equatable, Sendable, Codable {
    public var `continue`: Bool
    public var stopReason: String?
    public var suppressOutput: Bool
    public var systemMessage: String?

    enum CodingKeys: String, CodingKey {
        case `continue`
        case stopReason
        case suppressOutput
        case systemMessage
    }

    public init(
        `continue`: Bool = true,
        stopReason: String? = nil,
        suppressOutput: Bool = false,
        systemMessage: String? = nil
    ) {
        self.continue = `continue`
        self.stopReason = stopReason
        self.suppressOutput = suppressOutput
        self.systemMessage = systemMessage
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        `continue` = try container.decodeIfPresent(Bool.self, forKey: .continue) ?? true
        stopReason = try container.decodeIfPresent(String.self, forKey: .stopReason)
        suppressOutput = try container.decodeIfPresent(Bool.self, forKey: .suppressOutput) ?? false
        systemMessage = try container.decodeIfPresent(String.self, forKey: .systemMessage)
    }
}

public enum HookEventNameWire: String, Codable, Equatable, Sendable {
    case preToolUse = "PreToolUse"
    case permissionRequest = "PermissionRequest"
    case postToolUse = "PostToolUse"
    case preCompact = "PreCompact"
    case postCompact = "PostCompact"
    case sessionStart = "SessionStart"
    case userPromptSubmit = "UserPromptSubmit"
    case subagentStart = "SubagentStart"
    case subagentStop = "SubagentStop"
    case stop = "Stop"
    case interrupt = "Interrupt"
}

public func writeSchemaFixtures(outputDir: String) throws {
    _ = outputDir
    throw CodexErr.unsupportedOperation(
        "write_schema_fixtures waits on schemars-generated hook fixtures"
    )
}
