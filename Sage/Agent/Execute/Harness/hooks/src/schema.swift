//
//  schema.swift
//  CodexHooks
//
//  Port of codex-rs/hooks/src/schema.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Wire input/output structs used on hook stdin/stdout are ported.
//  `write_schema_fixtures` still waits on schemars-generated fixtures.
//

import CodexProtocol
import Foundation

public struct NullableString: Equatable, Sendable, Codable {
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

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = nil
        } else {
            value = try container.decode(String.self)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        if let value {
            try container.encode(value)
        } else {
            try container.encodeNil()
        }
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

public struct HookUniversalOutputWire: Equatable, Sendable {
    public var `continue`: Bool
    public var stopReason: String?
    public var suppressOutput: Bool
    public var systemMessage: String?

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

public enum PreToolUseDecisionWire: String, Equatable, Sendable {
    case approve
    case block
}

public enum PreToolUsePermissionDecisionWire: String, Equatable, Sendable {
    case allow
    case deny
    case ask
}

public enum PermissionRequestBehaviorWire: String, Equatable, Sendable {
    case allow
    case deny
}

public enum BlockDecisionWire: String, Equatable, Sendable {
    case block
}

public struct PreToolUseHookSpecificOutputWire: Equatable, Sendable {
    public var hookEventName: HookEventNameWire
    public var permissionDecision: PreToolUsePermissionDecisionWire?
    public var permissionDecisionReason: String?
    public var updatedInput: JSONValue?
    public var additionalContext: String?
}

public struct PostToolUseHookSpecificOutputWire: Equatable, Sendable {
    public var hookEventName: HookEventNameWire
    public var additionalContext: String?
    public var updatedMcpToolOutput: JSONValue?
}

public struct PermissionRequestDecisionWire: Equatable, Sendable {
    public var behavior: PermissionRequestBehaviorWire
    public var updatedInput: JSONValue?
    public var updatedPermissions: JSONValue?
    public var message: String?
    public var interrupt: Bool
}

public struct PermissionRequestHookSpecificOutputWire: Equatable, Sendable {
    public var hookEventName: HookEventNameWire
    public var decision: PermissionRequestDecisionWire?
}

public struct PreToolUseCommandOutputWire: Equatable, Sendable {
    public var universal: HookUniversalOutputWire
    public var decision: PreToolUseDecisionWire?
    public var reason: String?
    public var hookSpecificOutput: PreToolUseHookSpecificOutputWire?
}

public struct PostToolUseCommandOutputWire: Equatable, Sendable {
    public var universal: HookUniversalOutputWire
    public var decision: BlockDecisionWire?
    public var reason: String?
    public var hookSpecificOutput: PostToolUseHookSpecificOutputWire?
}

public struct PermissionRequestCommandOutputWire: Equatable, Sendable {
    public var universal: HookUniversalOutputWire
    public var hookSpecificOutput: PermissionRequestHookSpecificOutputWire?
}

public struct PreCompactCommandOutputWire: Equatable, Sendable {
    public var universal: HookUniversalOutputWire
}

public struct PostCompactCommandOutputWire: Equatable, Sendable {
    public var universal: HookUniversalOutputWire
}

public struct SessionStartHookSpecificOutputWire: Equatable, Sendable {
    public var hookEventName: HookEventNameWire
    public var additionalContext: String?
}

public struct SessionStartCommandOutputWire: Equatable, Sendable {
    public var universal: HookUniversalOutputWire
    public var hookSpecificOutput: SessionStartHookSpecificOutputWire?
}

public struct SubagentStartHookSpecificOutputWire: Equatable, Sendable {
    public var hookEventName: HookEventNameWire
    public var additionalContext: String?
}

public struct SubagentStartCommandOutputWire: Equatable, Sendable {
    public var universal: HookUniversalOutputWire
    public var hookSpecificOutput: SubagentStartHookSpecificOutputWire?
}

public struct UserPromptSubmitHookSpecificOutputWire: Equatable, Sendable {
    public var hookEventName: HookEventNameWire
    public var additionalContext: String?
}

public struct UserPromptSubmitCommandOutputWire: Equatable, Sendable {
    public var universal: HookUniversalOutputWire
    public var decision: BlockDecisionWire?
    public var reason: String?
    public var hookSpecificOutput: UserPromptSubmitHookSpecificOutputWire?
}

public struct StopCommandOutputWire: Equatable, Sendable {
    public var universal: HookUniversalOutputWire
    public var decision: BlockDecisionWire?
    public var reason: String?
}

public struct SubagentStopCommandOutputWire: Equatable, Sendable {
    public var universal: HookUniversalOutputWire
    public var decision: BlockDecisionWire?
    public var reason: String?
}

public struct InterruptCommandOutputWire: Equatable, Sendable {
    public var systemMessage: String?
}

public struct PreToolUseCommandInput: Equatable, Sendable {
    public var sessionId: String
    public var turnId: String
    public var agentId: String?
    public var agentType: String?
    public var transcriptPath: NullableString
    public var cwd: String
    public var hookEventName: String
    public var model: String
    public var permissionMode: String
    public var toolName: String
    public var toolInput: JSONValue
    public var toolUseId: String
}

public struct PermissionRequestCommandInput: Equatable, Sendable {
    public var sessionId: String
    public var turnId: String
    public var agentId: String?
    public var agentType: String?
    public var transcriptPath: NullableString
    public var cwd: String
    public var hookEventName: String
    public var model: String
    public var permissionMode: String
    public var toolName: String
    public var toolInput: JSONValue
}

public struct PostToolUseCommandInput: Equatable, Sendable {
    public var sessionId: String
    public var turnId: String
    public var agentId: String?
    public var agentType: String?
    public var transcriptPath: NullableString
    public var cwd: String
    public var hookEventName: String
    public var model: String
    public var permissionMode: String
    public var toolName: String
    public var toolInput: JSONValue
    public var toolResponse: JSONValue
    public var toolUseId: String
}

public struct PreCompactCommandInput: Equatable, Sendable {
    public var sessionId: String
    public var turnId: String
    public var agentId: String?
    public var agentType: String?
    public var transcriptPath: NullableString
    public var cwd: String
    public var hookEventName: String
    public var model: String
    public var trigger: String
}

public struct PostCompactCommandInput: Equatable, Sendable {
    public var sessionId: String
    public var turnId: String
    public var agentId: String?
    public var agentType: String?
    public var transcriptPath: NullableString
    public var cwd: String
    public var hookEventName: String
    public var model: String
    public var trigger: String
}

public struct SessionStartCommandInput: Equatable, Sendable {
    public var sessionId: String
    public var transcriptPath: NullableString
    public var cwd: String
    public var hookEventName: String
    public var model: String
    public var permissionMode: String
    public var source: String

    public init(
        sessionId: String,
        transcriptPath: String?,
        cwd: String,
        model: String,
        permissionMode: String,
        source: String
    ) {
        self.sessionId = sessionId
        self.transcriptPath = .fromPath(transcriptPath)
        self.cwd = cwd
        self.hookEventName = "SessionStart"
        self.model = model
        self.permissionMode = permissionMode
        self.source = source
    }
}

public struct SessionEndCommandInput: Equatable, Sendable {
    public var sessionId: String
    public var transcriptPath: NullableString
    public var cwd: String
    public var hookEventName: String
    public var reason: String
}

public struct SubagentStartCommandInput: Equatable, Sendable {
    public var sessionId: String
    public var turnId: String
    public var transcriptPath: NullableString
    public var cwd: String
    public var hookEventName: String
    public var model: String
    public var permissionMode: String
    public var agentId: String
    public var agentType: String
}

public struct UserPromptSubmitCommandInput: Equatable, Sendable {
    public var sessionId: String
    public var turnId: String
    public var agentId: String?
    public var agentType: String?
    public var transcriptPath: NullableString
    public var cwd: String
    public var hookEventName: String
    public var model: String
    public var permissionMode: String
    public var prompt: String
}

public struct StopCommandInput: Equatable, Sendable {
    public var sessionId: String
    public var turnId: String
    public var transcriptPath: NullableString
    public var cwd: String
    public var hookEventName: String
    public var model: String
    public var permissionMode: String
    public var stopHookActive: Bool
    public var lastAssistantMessage: NullableString
}

public struct SubagentStopCommandInput: Equatable, Sendable {
    public var sessionId: String
    public var turnId: String
    public var transcriptPath: NullableString
    public var agentTranscriptPath: NullableString
    public var cwd: String
    public var hookEventName: String
    public var model: String
    public var permissionMode: String
    public var stopHookActive: Bool
    public var agentId: String
    public var agentType: String
    public var lastAssistantMessage: NullableString
}

public struct InterruptCommandInput: Equatable, Sendable {
    public var sessionId: String
    public var turnId: String
    public var transcriptPath: NullableString
    public var cwd: String
    public var hookEventName: String
    public var model: String
    public var permissionMode: String
}

public func writeSchemaFixtures(outputDir: String) throws {
    _ = outputDir
    throw CodexErr.unsupportedOperation(
        "write_schema_fixtures waits on schemars-generated hook fixtures"
    )
}

func parseHookWireObject(_ stdout: String) -> [String: JSONValue]? {
    let trimmed = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return nil }
    guard let value = try? JSONDecoder().decode(JSONValue.self, from: data),
          case .object(let object) = value
    else { return nil }
    return object
}

func decodeHookWire<T>(_ stdout: String, _ decode: ([String: JSONValue]) -> T?) -> T? {
    guard let object = parseHookWireObject(stdout) else { return nil }
    return decode(object)
}

func rejectUnknownHookFields(_ object: [String: JSONValue], _ allowed: Set<String>) -> Bool {
    object.keys.allSatisfy(allowed.contains)
}

func hookBool(_ object: [String: JSONValue], _ key: String, default defaultValue: Bool) -> Bool? {
    guard let value = object[key] else { return defaultValue }
    if case .bool(let flag) = value { return flag }
    return nil
}

func hookOptionalString(_ object: [String: JSONValue], _ key: String) -> String?? {
    guard let value = object[key] else { return .some(nil) }
    switch value {
    case .null: return .some(nil)
    case .string(let text): return .some(text)
    default: return nil
    }
}

func hookOptionalValue(_ object: [String: JSONValue], _ key: String) -> JSONValue?? {
    guard let value = object[key] else { return .some(nil) }
    return .some(value == .null ? nil : value)
}

func hookOptionalObject(_ object: [String: JSONValue], _ key: String) -> [String: JSONValue]?? {
    guard let value = object[key] else { return .some(nil) }
    switch value {
    case .null: return .some(nil)
    case .object(let nested): return .some(nested)
    default: return nil
    }
}

func hookEventName(_ object: [String: JSONValue], _ key: String) -> HookEventNameWire? {
    guard case .string(let raw) = object[key] else { return nil }
    return HookEventNameWire(rawValue: raw)
}

func decodeUniversalOutput(_ object: [String: JSONValue]) -> HookUniversalOutputWire? {
    guard let continueProcessing = hookBool(object, "continue", default: true),
          let stopReason = hookOptionalString(object, "stopReason"),
          let suppressOutput = hookBool(object, "suppressOutput", default: false),
          let systemMessage = hookOptionalString(object, "systemMessage")
    else { return nil }
    return HookUniversalOutputWire(
        continue: continueProcessing,
        stopReason: stopReason,
        suppressOutput: suppressOutput,
        systemMessage: systemMessage
    )
}

func decodePreToolUseCommandOutputWire(_ object: [String: JSONValue]) -> PreToolUseCommandOutputWire? {
    guard rejectUnknownHookFields(object, [
        "continue", "stopReason", "suppressOutput", "systemMessage",
        "decision", "reason", "hookSpecificOutput",
    ]), let universal = decodeUniversalOutput(object) else { return nil }
    let decision: PreToolUseDecisionWire?
    if let raw = object["decision"] {
        guard case .string(let value) = raw,
              let parsed = PreToolUseDecisionWire(rawValue: value)
        else { return nil }
        decision = parsed
    } else {
        decision = nil
    }
    guard let reason = hookOptionalString(object, "reason"),
          let specific = hookOptionalObject(object, "hookSpecificOutput")
    else { return nil }
    let hookSpecificOutput: PreToolUseHookSpecificOutputWire?
    if let specific {
        hookSpecificOutput = decodePreToolUseHookSpecificOutput(specific)
        if hookSpecificOutput == nil { return nil }
    } else {
        hookSpecificOutput = nil
    }
    return PreToolUseCommandOutputWire(
        universal: universal, decision: decision, reason: reason,
        hookSpecificOutput: hookSpecificOutput
    )
}

func decodePreToolUseHookSpecificOutput(
    _ object: [String: JSONValue]
) -> PreToolUseHookSpecificOutputWire? {
    guard rejectUnknownHookFields(object, [
        "hookEventName", "permissionDecision", "permissionDecisionReason",
        "updatedInput", "additionalContext",
    ]), let hookEventName = hookEventName(object, "hookEventName") else { return nil }
    let permissionDecision: PreToolUsePermissionDecisionWire?
    if let raw = object["permissionDecision"] {
        guard case .string(let value) = raw,
              let parsed = PreToolUsePermissionDecisionWire(rawValue: value)
        else { return nil }
        permissionDecision = parsed
    } else {
        permissionDecision = nil
    }
    guard let permissionDecisionReason = hookOptionalString(object, "permissionDecisionReason"),
          let updatedInput = hookOptionalValue(object, "updatedInput"),
          let additionalContext = hookOptionalString(object, "additionalContext")
    else { return nil }
    return PreToolUseHookSpecificOutputWire(
        hookEventName: hookEventName,
        permissionDecision: permissionDecision,
        permissionDecisionReason: permissionDecisionReason,
        updatedInput: updatedInput,
        additionalContext: additionalContext
    )
}

func decodePostToolUseCommandOutputWire(_ object: [String: JSONValue]) -> PostToolUseCommandOutputWire? {
    guard rejectUnknownHookFields(object, [
        "continue", "stopReason", "suppressOutput", "systemMessage",
        "decision", "reason", "hookSpecificOutput",
    ]), let universal = decodeUniversalOutput(object) else { return nil }
    let decision: BlockDecisionWire?
    if let raw = object["decision"] {
        guard case .string(let value) = raw, let parsed = BlockDecisionWire(rawValue: value) else {
            return nil
        }
        decision = parsed
    } else {
        decision = nil
    }
    guard let reason = hookOptionalString(object, "reason"),
          let specific = hookOptionalObject(object, "hookSpecificOutput")
    else { return nil }
    let hookSpecificOutput: PostToolUseHookSpecificOutputWire?
    if let specific {
        hookSpecificOutput = decodePostToolUseHookSpecificOutput(specific)
        if hookSpecificOutput == nil { return nil }
    } else {
        hookSpecificOutput = nil
    }
    return PostToolUseCommandOutputWire(
        universal: universal, decision: decision, reason: reason,
        hookSpecificOutput: hookSpecificOutput
    )
}

func decodePostToolUseHookSpecificOutput(
    _ object: [String: JSONValue]
) -> PostToolUseHookSpecificOutputWire? {
    guard rejectUnknownHookFields(object, [
        "hookEventName", "additionalContext", "updatedMCPToolOutput",
    ]), let hookEventName = hookEventName(object, "hookEventName"),
        let additionalContext = hookOptionalString(object, "additionalContext"),
        let updatedMcpToolOutput = hookOptionalValue(object, "updatedMCPToolOutput")
    else { return nil }
    return PostToolUseHookSpecificOutputWire(
        hookEventName: hookEventName,
        additionalContext: additionalContext,
        updatedMcpToolOutput: updatedMcpToolOutput
    )
}

func decodePermissionRequestCommandOutputWire(
    _ object: [String: JSONValue]
) -> PermissionRequestCommandOutputWire? {
    guard rejectUnknownHookFields(object, [
        "continue", "stopReason", "suppressOutput", "systemMessage", "hookSpecificOutput",
    ]), let universal = decodeUniversalOutput(object),
        let specific = hookOptionalObject(object, "hookSpecificOutput")
    else { return nil }
    let hookSpecificOutput: PermissionRequestHookSpecificOutputWire?
    if let specific {
        hookSpecificOutput = decodePermissionRequestHookSpecificOutput(specific)
        if hookSpecificOutput == nil { return nil }
    } else {
        hookSpecificOutput = nil
    }
    return PermissionRequestCommandOutputWire(
        universal: universal, hookSpecificOutput: hookSpecificOutput
    )
}

func decodePermissionRequestHookSpecificOutput(
    _ object: [String: JSONValue]
) -> PermissionRequestHookSpecificOutputWire? {
    guard rejectUnknownHookFields(object, ["hookEventName", "decision"]),
          let hookEventName = hookEventName(object, "hookEventName"),
          let decisionObject = hookOptionalObject(object, "decision")
    else { return nil }
    let decision: PermissionRequestDecisionWire?
    if let decisionObject {
        decision = decodePermissionRequestDecision(decisionObject)
        if decision == nil { return nil }
    } else {
        decision = nil
    }
    return PermissionRequestHookSpecificOutputWire(hookEventName: hookEventName, decision: decision)
}

func decodePermissionRequestDecision(
    _ object: [String: JSONValue]
) -> PermissionRequestDecisionWire? {
    guard rejectUnknownHookFields(object, [
        "behavior", "updatedInput", "updatedPermissions", "message", "interrupt",
    ]), case .string(let raw) = object["behavior"],
        let behavior = PermissionRequestBehaviorWire(rawValue: raw),
        let updatedInput = hookOptionalValue(object, "updatedInput"),
        let updatedPermissions = hookOptionalValue(object, "updatedPermissions"),
        let message = hookOptionalString(object, "message"),
        let interrupt = hookBool(object, "interrupt", default: false)
    else { return nil }
    return PermissionRequestDecisionWire(
        behavior: behavior,
        updatedInput: updatedInput,
        updatedPermissions: updatedPermissions,
        message: message,
        interrupt: interrupt
    )
}

func decodeStatelessCommandOutputWire(_ object: [String: JSONValue]) -> HookUniversalOutputWire? {
    guard rejectUnknownHookFields(object, [
        "continue", "stopReason", "suppressOutput", "systemMessage",
    ]) else { return nil }
    return decodeUniversalOutput(object)
}

func decodeSessionStartCommandOutputWire(
    _ object: [String: JSONValue]
) -> SessionStartCommandOutputWire? {
    decodeStartLikeOutput(object, decodeSpecific: decodeSessionStartHookSpecificOutput)
}

func decodeSubagentStartCommandOutputWire(
    _ object: [String: JSONValue]
) -> SubagentStartCommandOutputWire? {
    guard let parsed = decodeStartLikeOutput(
        object, decodeSpecific: decodeSubagentStartHookSpecificOutput
    ) else { return nil }
    return SubagentStartCommandOutputWire(
        universal: parsed.universal,
        hookSpecificOutput: parsed.hookSpecificOutput.map {
            SubagentStartHookSpecificOutputWire(
                hookEventName: $0.hookEventName, additionalContext: $0.additionalContext
            )
        }
    )
}

func decodeUserPromptSubmitCommandOutputWire(
    _ object: [String: JSONValue]
) -> UserPromptSubmitCommandOutputWire? {
    guard rejectUnknownHookFields(object, [
        "continue", "stopReason", "suppressOutput", "systemMessage",
        "decision", "reason", "hookSpecificOutput",
    ]), let universal = decodeUniversalOutput(object) else { return nil }
    let decision: BlockDecisionWire?
    if let raw = object["decision"] {
        guard case .string(let value) = raw, let parsed = BlockDecisionWire(rawValue: value) else {
            return nil
        }
        decision = parsed
    } else {
        decision = nil
    }
    guard let reason = hookOptionalString(object, "reason"),
          let specific = hookOptionalObject(object, "hookSpecificOutput")
    else { return nil }
    let hookSpecificOutput: UserPromptSubmitHookSpecificOutputWire?
    if let specific {
        guard rejectUnknownHookFields(specific, ["hookEventName", "additionalContext"]),
              let hookEventName = hookEventName(specific, "hookEventName"),
              let additionalContext = hookOptionalString(specific, "additionalContext")
        else { return nil }
        hookSpecificOutput = UserPromptSubmitHookSpecificOutputWire(
            hookEventName: hookEventName, additionalContext: additionalContext
        )
    } else {
        hookSpecificOutput = nil
    }
    return UserPromptSubmitCommandOutputWire(
        universal: universal, decision: decision, reason: reason,
        hookSpecificOutput: hookSpecificOutput
    )
}

func decodeStopCommandOutputWire(_ object: [String: JSONValue]) -> StopCommandOutputWire? {
    decodeBlockDecisionOutput(object)
}

func decodeSubagentStopCommandOutputWire(
    _ object: [String: JSONValue]
) -> SubagentStopCommandOutputWire? {
    guard let parsed = decodeBlockDecisionOutput(object) else { return nil }
    return SubagentStopCommandOutputWire(
        universal: parsed.universal, decision: parsed.decision, reason: parsed.reason
    )
}

func decodeInterruptCommandOutputWire(_ object: [String: JSONValue]) -> InterruptCommandOutputWire? {
    guard rejectUnknownHookFields(object, ["systemMessage"]),
          let systemMessage = hookOptionalString(object, "systemMessage")
    else { return nil }
    return InterruptCommandOutputWire(systemMessage: systemMessage)
}

private func decodeStartLikeOutput(
    _ object: [String: JSONValue],
    decodeSpecific: ([String: JSONValue]) -> SessionStartHookSpecificOutputWire?
) -> SessionStartCommandOutputWire? {
    guard rejectUnknownHookFields(object, [
        "continue", "stopReason", "suppressOutput", "systemMessage", "hookSpecificOutput",
    ]), let universal = decodeUniversalOutput(object),
        let specific = hookOptionalObject(object, "hookSpecificOutput")
    else { return nil }
    let hookSpecificOutput: SessionStartHookSpecificOutputWire?
    if let specific {
        hookSpecificOutput = decodeSpecific(specific)
        if hookSpecificOutput == nil { return nil }
    } else {
        hookSpecificOutput = nil
    }
    return SessionStartCommandOutputWire(
        universal: universal, hookSpecificOutput: hookSpecificOutput
    )
}

private func decodeSessionStartHookSpecificOutput(
    _ object: [String: JSONValue]
) -> SessionStartHookSpecificOutputWire? {
    guard rejectUnknownHookFields(object, ["hookEventName", "additionalContext"]),
          let hookEventName = hookEventName(object, "hookEventName"),
          let additionalContext = hookOptionalString(object, "additionalContext")
    else { return nil }
    return SessionStartHookSpecificOutputWire(
        hookEventName: hookEventName, additionalContext: additionalContext
    )
}

private func decodeSubagentStartHookSpecificOutput(
    _ object: [String: JSONValue]
) -> SessionStartHookSpecificOutputWire? {
    decodeSessionStartHookSpecificOutput(object)
}

func encodeHookInput(_ pairs: [(String, JSONValue)], skipIfNull: Set<String> = []) -> String {
    var object: [String: JSONValue] = [:]
    for (key, value) in pairs {
        if case .null = value, skipIfNull.contains(key) { continue }
        object[key] = value
    }
    return JSONValue.object(object).encodedString()
}

func hookNullableJSON(_ value: NullableString) -> JSONValue {
    value.value.map(JSONValue.string) ?? .null
}

func hookOptionalStringJSON(_ value: String?) -> JSONValue {
    value.map(JSONValue.string) ?? .null
}

extension PreToolUseCommandInput {
    public func encodedJSON() -> String {
        encodeHookInput([
            ("session_id", .string(sessionId)),
            ("turn_id", .string(turnId)),
            ("agent_id", hookOptionalStringJSON(agentId)),
            ("agent_type", hookOptionalStringJSON(agentType)),
            ("transcript_path", hookNullableJSON(transcriptPath)),
            ("cwd", .string(cwd)),
            ("hook_event_name", .string(hookEventName)),
            ("model", .string(model)),
            ("permission_mode", .string(permissionMode)),
            ("tool_name", .string(toolName)),
            ("tool_input", toolInput),
            ("tool_use_id", .string(toolUseId)),
        ], skipIfNull: ["agent_id", "agent_type"])
    }
}

extension PostToolUseCommandInput {
    public func encodedJSON() -> String {
        encodeHookInput([
            ("session_id", .string(sessionId)),
            ("turn_id", .string(turnId)),
            ("agent_id", hookOptionalStringJSON(agentId)),
            ("agent_type", hookOptionalStringJSON(agentType)),
            ("transcript_path", hookNullableJSON(transcriptPath)),
            ("cwd", .string(cwd)),
            ("hook_event_name", .string(hookEventName)),
            ("model", .string(model)),
            ("permission_mode", .string(permissionMode)),
            ("tool_name", .string(toolName)),
            ("tool_input", toolInput),
            ("tool_response", toolResponse),
            ("tool_use_id", .string(toolUseId)),
        ], skipIfNull: ["agent_id", "agent_type"])
    }
}

extension PermissionRequestCommandInput {
    public func encodedJSON() -> String {
        encodeHookInput([
            ("session_id", .string(sessionId)),
            ("turn_id", .string(turnId)),
            ("agent_id", hookOptionalStringJSON(agentId)),
            ("agent_type", hookOptionalStringJSON(agentType)),
            ("transcript_path", hookNullableJSON(transcriptPath)),
            ("cwd", .string(cwd)),
            ("hook_event_name", .string(hookEventName)),
            ("model", .string(model)),
            ("permission_mode", .string(permissionMode)),
            ("tool_name", .string(toolName)),
            ("tool_input", toolInput),
        ], skipIfNull: ["agent_id", "agent_type"])
    }
}

extension UserPromptSubmitCommandInput {
    public func encodedJSON() -> String {
        encodeHookInput([
            ("session_id", .string(sessionId)),
            ("turn_id", .string(turnId)),
            ("agent_id", hookOptionalStringJSON(agentId)),
            ("agent_type", hookOptionalStringJSON(agentType)),
            ("transcript_path", hookNullableJSON(transcriptPath)),
            ("cwd", .string(cwd)),
            ("hook_event_name", .string(hookEventName)),
            ("model", .string(model)),
            ("permission_mode", .string(permissionMode)),
            ("prompt", .string(prompt)),
        ], skipIfNull: ["agent_id", "agent_type"])
    }
}

extension PreCompactCommandInput {
    public func encodedJSON() -> String {
        encodeHookInput([
            ("session_id", .string(sessionId)),
            ("turn_id", .string(turnId)),
            ("agent_id", hookOptionalStringJSON(agentId)),
            ("agent_type", hookOptionalStringJSON(agentType)),
            ("transcript_path", hookNullableJSON(transcriptPath)),
            ("cwd", .string(cwd)),
            ("hook_event_name", .string(hookEventName)),
            ("model", .string(model)),
            ("trigger", .string(trigger)),
        ], skipIfNull: ["agent_id", "agent_type"])
    }
}

extension PostCompactCommandInput {
    public func encodedJSON() -> String {
        encodeHookInput([
            ("session_id", .string(sessionId)),
            ("turn_id", .string(turnId)),
            ("agent_id", hookOptionalStringJSON(agentId)),
            ("agent_type", hookOptionalStringJSON(agentType)),
            ("transcript_path", hookNullableJSON(transcriptPath)),
            ("cwd", .string(cwd)),
            ("hook_event_name", .string(hookEventName)),
            ("model", .string(model)),
            ("trigger", .string(trigger)),
        ], skipIfNull: ["agent_id", "agent_type"])
    }
}

extension InterruptCommandInput {
    public func encodedJSON() -> String {
        encodeHookInput([
            ("session_id", .string(sessionId)),
            ("turn_id", .string(turnId)),
            ("transcript_path", hookNullableJSON(transcriptPath)),
            ("cwd", .string(cwd)),
            ("hook_event_name", .string(hookEventName)),
            ("model", .string(model)),
            ("permission_mode", .string(permissionMode)),
        ])
    }
}

extension SessionStartCommandInput {
    public func encodedJSON() -> String {
        encodeHookInput([
            ("session_id", .string(sessionId)),
            ("transcript_path", hookNullableJSON(transcriptPath)),
            ("cwd", .string(cwd)),
            ("hook_event_name", .string(hookEventName)),
            ("model", .string(model)),
            ("permission_mode", .string(permissionMode)),
            ("source", .string(source)),
        ])
    }
}

extension SessionEndCommandInput {
    public func encodedJSON() -> String {
        encodeHookInput([
            ("session_id", .string(sessionId)),
            ("transcript_path", hookNullableJSON(transcriptPath)),
            ("cwd", .string(cwd)),
            ("hook_event_name", .string(hookEventName)),
            ("reason", .string(reason)),
        ])
    }
}

extension SubagentStartCommandInput {
    public func encodedJSON() -> String {
        encodeHookInput([
            ("session_id", .string(sessionId)),
            ("turn_id", .string(turnId)),
            ("transcript_path", hookNullableJSON(transcriptPath)),
            ("cwd", .string(cwd)),
            ("hook_event_name", .string(hookEventName)),
            ("model", .string(model)),
            ("permission_mode", .string(permissionMode)),
            ("agent_id", .string(agentId)),
            ("agent_type", .string(agentType)),
        ])
    }
}

extension StopCommandInput {
    public func encodedJSON() -> String {
        encodeHookInput([
            ("session_id", .string(sessionId)),
            ("turn_id", .string(turnId)),
            ("transcript_path", hookNullableJSON(transcriptPath)),
            ("cwd", .string(cwd)),
            ("hook_event_name", .string(hookEventName)),
            ("model", .string(model)),
            ("permission_mode", .string(permissionMode)),
            ("stop_hook_active", .bool(stopHookActive)),
            ("last_assistant_message", hookNullableJSON(lastAssistantMessage)),
        ])
    }
}

extension SubagentStopCommandInput {
    public func encodedJSON() -> String {
        encodeHookInput([
            ("session_id", .string(sessionId)),
            ("turn_id", .string(turnId)),
            ("transcript_path", hookNullableJSON(transcriptPath)),
            ("agent_transcript_path", hookNullableJSON(agentTranscriptPath)),
            ("cwd", .string(cwd)),
            ("hook_event_name", .string(hookEventName)),
            ("model", .string(model)),
            ("permission_mode", .string(permissionMode)),
            ("stop_hook_active", .bool(stopHookActive)),
            ("agent_id", .string(agentId)),
            ("agent_type", .string(agentType)),
            ("last_assistant_message", hookNullableJSON(lastAssistantMessage)),
        ])
    }
}

private func decodeBlockDecisionOutput(_ object: [String: JSONValue]) -> StopCommandOutputWire? {
    guard rejectUnknownHookFields(object, [
        "continue", "stopReason", "suppressOutput", "systemMessage", "decision", "reason",
    ]), let universal = decodeUniversalOutput(object) else { return nil }
    let decision: BlockDecisionWire?
    if let raw = object["decision"] {
        guard case .string(let value) = raw, let parsed = BlockDecisionWire(rawValue: value) else {
            return nil
        }
        decision = parsed
    } else {
        decision = nil
    }
    guard let reason = hookOptionalString(object, "reason") else { return nil }
    return StopCommandOutputWire(universal: universal, decision: decision, reason: reason)
}
