//
//  output_parser.swift
//  CodexHooks
//
//  Port of codex-rs/hooks/src/engine/output_parser.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Per-event schema decode plus the semantic reject rules for reserved
//  or incomplete hook fields. JSON Schema fixture generation stays out.
//  `PermissionRequestDecision` is the event type; rust keeps a second copy
//  in events/permission_request.rs.
//

import CodexProtocol
import Foundation

public struct HookUniversalOutput: Equatable, Sendable {
    public var continueProcessing: Bool
    public var stopReason: String?
    public var suppressOutput: Bool
    public var systemMessage: String?

    public var `continue`: Bool {
        get { continueProcessing }
        set { continueProcessing = newValue }
    }

    public init(
        continueProcessing: Bool = true,
        stopReason: String? = nil,
        suppressOutput: Bool = false,
        systemMessage: String? = nil
    ) {
        self.continueProcessing = continueProcessing
        self.stopReason = stopReason
        self.suppressOutput = suppressOutput
        self.systemMessage = systemMessage
    }

    public init(
        `continue`: Bool,
        stopReason: String? = nil,
        suppressOutput: Bool = false,
        systemMessage: String? = nil
    ) {
        self.init(
            continueProcessing: `continue`,
            stopReason: stopReason,
            suppressOutput: suppressOutput,
            systemMessage: systemMessage
        )
    }
}

public struct SessionStartOutput: Equatable, Sendable {
    public var universal: HookUniversalOutput
    public var additionalContext: String?
}

public struct PreToolUseOutput: Equatable, Sendable {
    public var universal: HookUniversalOutput
    public var blockReason: String?
    public var additionalContext: String?
    public var updatedInput: JSONValue?
    public var invalidReason: String?
}

/// Shared with `events/permission_request.swift`. Rust keeps a second copy
/// in the event module; Swift has one module.
public enum PermissionRequestDecision: Equatable, Sendable {
    case allow
    case deny(message: String)
}

public struct PermissionRequestOutput: Equatable, Sendable {
    public var universal: HookUniversalOutput
    public var decision: PermissionRequestDecision?
    public var invalidReason: String?
}

public struct PostToolUseOutput: Equatable, Sendable {
    public var universal: HookUniversalOutput
    public var shouldBlock: Bool
    public var reason: String?
    public var invalidBlockReason: String?
    public var additionalContext: String?
    public var invalidReason: String?
}

public struct UserPromptSubmitOutput: Equatable, Sendable {
    public var universal: HookUniversalOutput
    public var shouldBlock: Bool
    public var reason: String?
    public var invalidBlockReason: String?
    public var additionalContext: String?
}

public struct StopOutput: Equatable, Sendable {
    public var universal: HookUniversalOutput
    public var shouldBlock: Bool
    public var reason: String?
    public var invalidBlockReason: String?
}

public struct StatelessHookOutput: Equatable, Sendable {
    public var universal: HookUniversalOutput
    public var invalidReason: String?
}

public struct InterruptOutput: Equatable, Sendable {
    public var systemMessage: String?
}

public func looksLikeJSON(_ stdout: String) -> Bool {
    let trimmed = stdout.drop(while: { $0.isWhitespace })
    return trimmed.hasPrefix("{") || trimmed.hasPrefix("[")
}

public func parseUniversalHookOutput(_ stdout: String) -> HookUniversalOutput? {
    guard let object = parseHookWireObject(stdout),
          rejectUnknownHookFields(object, [
              "continue", "stopReason", "suppressOutput", "systemMessage",
          ]),
          let wire = decodeUniversalOutput(object)
    else { return nil }
    return HookUniversalOutput(wire)
}

public func parseSessionStart(_ stdout: String) -> SessionStartOutput? {
    decodeHookWire(stdout, decodeSessionStartCommandOutputWire).map {
        SessionStartOutput(
            universal: HookUniversalOutput($0.universal),
            additionalContext: $0.hookSpecificOutput?.additionalContext
        )
    }
}

public func parseSubagentStart(_ stdout: String) -> SessionStartOutput? {
    decodeHookWire(stdout, decodeSubagentStartCommandOutputWire).map {
        SessionStartOutput(
            universal: HookUniversalOutput($0.universal),
            additionalContext: $0.hookSpecificOutput?.additionalContext
        )
    }
}

public func parsePreToolUse(_ stdout: String) -> PreToolUseOutput? {
    guard let wire = decodeHookWire(stdout, decodePreToolUseCommandOutputWire) else { return nil }
    let universal = HookUniversalOutput(wire.universal)
    let hookSpecificOutput = wire.hookSpecificOutput
    let additionalContext = hookSpecificOutput?.additionalContext
    let useHookSpecificDecision = hookSpecificOutput.map { output in
        output.permissionDecision != nil
            || output.permissionDecisionReason != nil
            || output.updatedInput != nil
    } ?? false
    let invalidReason = unsupportedPreToolUseUniversal(universal) ?? {
        if useHookSpecificDecision {
            return hookSpecificOutput.flatMap(unsupportedPreToolUseHookSpecificOutput)
        }
        return unsupportedPreToolUseLegacyDecision(wire.decision, reason: wire.reason)
    }()
    let blockReason: String?
    if invalidReason == nil {
        if useHookSpecificDecision {
            if hookSpecificOutput?.permissionDecision == .deny {
                blockReason = hookSpecificOutput?.permissionDecisionReason.flatMap(trimmedReason)
            } else {
                blockReason = nil
            }
        } else if wire.decision == .block {
            blockReason = wire.reason.flatMap(trimmedReason)
        } else {
            blockReason = nil
        }
    } else {
        blockReason = nil
    }
    let updatedInput: JSONValue?
    if invalidReason == nil, hookSpecificOutput?.permissionDecision == .allow {
        updatedInput = hookSpecificOutput?.updatedInput
    } else {
        updatedInput = nil
    }
    return PreToolUseOutput(
        universal: universal,
        blockReason: blockReason,
        additionalContext: additionalContext,
        updatedInput: updatedInput,
        invalidReason: invalidReason
    )
}

public func parsePermissionRequest(_ stdout: String) -> PermissionRequestOutput? {
    guard let wire = decodeHookWire(stdout, decodePermissionRequestCommandOutputWire) else {
        return nil
    }
    let universal = HookUniversalOutput(wire.universal)
    let decisionWire = wire.hookSpecificOutput?.decision
    let invalidReason = unsupportedPermissionRequestUniversal(universal)
        ?? unsupportedPermissionRequestHookSpecificOutput(decisionWire)
    let decision = invalidReason == nil ? decisionWire.map(permissionRequestDecision) : nil
    return PermissionRequestOutput(
        universal: universal,
        decision: decision,
        invalidReason: invalidReason
    )
}

public func parsePostToolUse(_ stdout: String) -> PostToolUseOutput? {
    guard let wire = decodeHookWire(stdout, decodePostToolUseCommandOutputWire) else { return nil }
    let universal = HookUniversalOutput(wire.universal)
    let invalidReason = unsupportedPostToolUseUniversal(universal)
        ?? wire.hookSpecificOutput.flatMap(unsupportedPostToolUseHookSpecificOutput)
    let shouldBlock = wire.decision == .block
    let invalidBlockReason: String?
    if shouldBlock, wire.reason.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) ?? true {
        invalidBlockReason = invalidBlockMessage("PostToolUse")
    } else if !shouldBlock, universal.continueProcessing, wire.reason != nil {
        invalidBlockReason = "PostToolUse hook returned reason without decision"
    } else {
        invalidBlockReason = nil
    }
    return PostToolUseOutput(
        universal: universal,
        shouldBlock: shouldBlock && invalidReason == nil && invalidBlockReason == nil,
        reason: wire.reason,
        invalidBlockReason: invalidBlockReason,
        additionalContext: wire.hookSpecificOutput?.additionalContext,
        invalidReason: invalidReason
    )
}

public func parsePreCompact(_ stdout: String) -> StatelessHookOutput? {
    decodeHookWire(stdout, decodeStatelessCommandOutputWire).map {
        StatelessHookOutput(universal: HookUniversalOutput($0), invalidReason: nil)
    }
}

public func parsePostCompact(_ stdout: String) -> StatelessHookOutput? {
    decodeHookWire(stdout, decodeStatelessCommandOutputWire).map {
        StatelessHookOutput(universal: HookUniversalOutput($0), invalidReason: nil)
    }
}

public func parseInterrupt(_ stdout: String) -> InterruptOutput? {
    decodeHookWire(stdout, decodeInterruptCommandOutputWire).map {
        InterruptOutput(systemMessage: $0.systemMessage)
    }
}

public func parseUserPromptSubmit(_ stdout: String) -> UserPromptSubmitOutput? {
    guard let wire = decodeHookWire(stdout, decodeUserPromptSubmitCommandOutputWire) else {
        return nil
    }
    let shouldBlock = wire.decision == .block
    let invalidBlockReason: String?
    if shouldBlock, wire.reason.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) ?? true {
        invalidBlockReason = invalidBlockMessage("UserPromptSubmit")
    } else {
        invalidBlockReason = nil
    }
    return UserPromptSubmitOutput(
        universal: HookUniversalOutput(wire.universal),
        shouldBlock: shouldBlock && invalidBlockReason == nil,
        reason: wire.reason,
        invalidBlockReason: invalidBlockReason,
        additionalContext: wire.hookSpecificOutput?.additionalContext
    )
}

public func parseStop(_ stdout: String) -> StopOutput? {
    decodeHookWire(stdout, decodeStopCommandOutputWire).map {
        stopOutput($0.universal, decision: $0.decision, reason: $0.reason, eventName: "Stop")
    }
}

public func parseSubagentStop(_ stdout: String) -> StopOutput? {
    decodeHookWire(stdout, decodeSubagentStopCommandOutputWire).map {
        stopOutput($0.universal, decision: $0.decision, reason: $0.reason, eventName: "SubagentStop")
    }
}

private func stopOutput(
    _ universal: HookUniversalOutputWire,
    decision: BlockDecisionWire?,
    reason: String?,
    eventName: String
) -> StopOutput {
    let shouldBlock = decision == .block
    let invalidBlockReason: String?
    if shouldBlock, reason.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) ?? true {
        invalidBlockReason = invalidBlockMessage(eventName)
    } else {
        invalidBlockReason = nil
    }
    return StopOutput(
        universal: HookUniversalOutput(universal),
        shouldBlock: shouldBlock && invalidBlockReason == nil,
        reason: reason,
        invalidBlockReason: invalidBlockReason
    )
}

private extension HookUniversalOutput {
    init(_ wire: HookUniversalOutputWire) {
        self.init(
            continueProcessing: wire.continue,
            stopReason: wire.stopReason,
            suppressOutput: wire.suppressOutput,
            systemMessage: wire.systemMessage
        )
    }
}

private func invalidBlockMessage(_ eventName: String) -> String {
    "\(eventName) hook returned decision:block without a non-empty reason"
}

private func unsupportedPreToolUseUniversal(_ universal: HookUniversalOutput) -> String? {
    if !universal.continueProcessing {
        return "PreToolUse hook returned unsupported continue:false"
    }
    if universal.stopReason != nil {
        return "PreToolUse hook returned unsupported stopReason"
    }
    if universal.suppressOutput {
        return "PreToolUse hook returned unsupported suppressOutput"
    }
    return nil
}

private func unsupportedPermissionRequestUniversal(_ universal: HookUniversalOutput) -> String? {
    if !universal.continueProcessing {
        return "PermissionRequest hook returned unsupported continue:false"
    }
    if universal.stopReason != nil {
        return "PermissionRequest hook returned unsupported stopReason"
    }
    if universal.suppressOutput {
        return "PermissionRequest hook returned unsupported suppressOutput"
    }
    return nil
}

private func unsupportedPostToolUseUniversal(_ universal: HookUniversalOutput) -> String? {
    universal.suppressOutput ? "PostToolUse hook returned unsupported suppressOutput" : nil
}

private func unsupportedPermissionRequestHookSpecificOutput(
    _ decision: PermissionRequestDecisionWire?
) -> String? {
    guard let decision else { return nil }
    if decision.updatedInput != nil {
        return "PermissionRequest hook returned unsupported updatedInput"
    }
    if decision.updatedPermissions != nil {
        return "PermissionRequest hook returned unsupported updatedPermissions"
    }
    if decision.interrupt {
        return "PermissionRequest hook returned unsupported interrupt:true"
    }
    return nil
}

private func permissionRequestDecision(
    _ decision: PermissionRequestDecisionWire
) -> PermissionRequestDecision {
    switch decision.behavior {
    case .allow:
        return .allow
    case .deny:
        return .deny(
            message: decision.message.flatMap(trimmedReason)
                ?? "PermissionRequest hook denied approval"
        )
    }
}

private func unsupportedPostToolUseHookSpecificOutput(
    _ output: PostToolUseHookSpecificOutputWire
) -> String? {
    output.updatedMcpToolOutput == nil
        ? nil
        : "PostToolUse hook returned unsupported updatedMCPToolOutput"
}

private func unsupportedPreToolUseHookSpecificOutput(
    _ output: PreToolUseHookSpecificOutputWire
) -> String? {
    if output.updatedInput != nil, output.permissionDecision != .allow {
        return "PreToolUse hook returned updatedInput without permissionDecision:allow"
    }
    switch output.permissionDecision {
    case .allow:
        return output.updatedInput == nil
            ? "PreToolUse hook returned unsupported permissionDecision:allow"
            : nil
    case .ask:
        return "PreToolUse hook returned unsupported permissionDecision:ask"
    case .deny:
        return output.permissionDecisionReason.flatMap(trimmedReason) == nil
            ? invalidPreToolUseReasonMessage()
            : nil
    case nil:
        return output.permissionDecisionReason == nil
            ? nil
            : "PreToolUse hook returned permissionDecisionReason without permissionDecision"
    }
}

private func unsupportedPreToolUseLegacyDecision(
    _ decision: PreToolUseDecisionWire?,
    reason: String?
) -> String? {
    switch decision {
    case .approve:
        return "PreToolUse hook returned unsupported decision:approve"
    case .block:
        return reason.flatMap(trimmedReason) == nil
            ? invalidBlockMessage("PreToolUse")
            : nil
    case nil:
        return reason == nil ? nil : "PreToolUse hook returned reason without decision"
    }
}

private func invalidPreToolUseReasonMessage() -> String {
    "PreToolUse hook returned permissionDecision:deny without a non-empty permissionDecisionReason"
}

private func trimmedReason(_ reason: String) -> String? {
    let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}
