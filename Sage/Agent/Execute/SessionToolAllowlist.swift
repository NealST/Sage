//
//  SessionToolAllowlist.swift
//  Sage
//
//  Remembers exact shell / MCP invocations the user approved for this task.
//

import CryptoKit
import Foundation

/// Task-scoped approvals for tools that stay gated after an `act` plan confirm.
/// Reset when the window switches tasks (`beginNewTask` / `activateTask`).
@MainActor
final class SessionToolAllowlist {
    private var capabilityOneShotKeys: Set<String> = []
    private var hookOneShotKeys: Set<String> = []
    private let grantStore: ToolAuthorizationGrantStore

    init(grantStore: ToolAuthorizationGrantStore = .shared) {
        self.grantStore = grantStore
    }

    nonisolated static func needsGate(
        name: String,
        argumentsJSON: String,
        policy: PathGuard.Policy,
        skills: [SkillRecord] = [],
        mcpTools: [MCPToolInfo] = []
    ) -> Bool {
        ToolAuthorizationPolicy.requirement(
            name: name,
            argumentsJSON: argumentsJSON,
            policy: policy,
            skills: skills,
            mcpTools: mcpTools
        ) != nil
    }

    func contains(
        name: String,
        argumentsJSON: String,
        policy: PathGuard.Policy,
        scopeID: String,
        skills: [SkillRecord] = [],
        mcpTools: [MCPToolInfo] = []
    ) -> Bool {
        guard let requirement = ToolAuthorizationPolicy.requirement(
            name: name,
            argumentsJSON: argumentsJSON,
            policy: policy,
            skills: skills,
            mcpTools: mcpTools
        ) else { return true }
        let key = Self.capabilityKey(
            name: name,
            argumentsJSON: argumentsJSON,
            requirement: requirement
        )
        return capabilityOneShotKeys.contains(key)
            || grantStore.contains(requirement, scopeID: scopeID)
    }

    /// Returns approval and consumes an Allow Once grant exactly once.
    func consumeApproval(
        name: String,
        argumentsJSON: String,
        policy: PathGuard.Policy,
        scopeID: String,
        skills: [SkillRecord] = [],
        mcpTools: [MCPToolInfo] = []
    ) -> Bool {
        guard let requirement = ToolAuthorizationPolicy.requirement(
            name: name,
            argumentsJSON: argumentsJSON,
            policy: policy,
            skills: skills,
            mcpTools: mcpTools
        ) else { return true }
        let key = Self.capabilityKey(
            name: name,
            argumentsJSON: argumentsJSON,
            requirement: requirement
        )
        if capabilityOneShotKeys.remove(key) != nil { return true }
        return grantStore.contains(requirement, scopeID: scopeID)
    }

    func allowCapabilityOnce(
        name: String,
        argumentsJSON: String,
        policy: PathGuard.Policy,
        skills: [SkillRecord] = [],
        mcpTools: [MCPToolInfo] = []
    ) {
        guard let requirement = ToolAuthorizationPolicy.requirement(
            name: name,
            argumentsJSON: argumentsJSON,
            policy: policy,
            skills: skills,
            mcpTools: mcpTools
        ) else { return }
        capabilityOneShotKeys.insert(
            Self.capabilityKey(
                name: name,
                argumentsJSON: argumentsJSON,
                requirement: requirement
            )
        )
        grantStore.rememberDirectoryRoots(requirement)
    }

    func containsHookApproval(
        name: String,
        argumentsJSON: String,
        hookIdentity: String,
        scopeID: String
    ) -> Bool {
        let key = Self.hookApprovalKey(
            name: name,
            argumentsJSON: argumentsJSON,
            hookIdentity: hookIdentity
        )
        return hookOneShotKeys.contains(key)
            || grantStore.containsInvocation(key, scopeID: scopeID)
    }

    func consumeHookApproval(
        name: String,
        argumentsJSON: String,
        hookIdentity: String,
        scopeID: String
    ) -> Bool {
        let key = Self.hookApprovalKey(
            name: name,
            argumentsJSON: argumentsJSON,
            hookIdentity: hookIdentity
        )
        if hookOneShotKeys.remove(key) != nil { return true }
        return grantStore.containsInvocation(key, scopeID: scopeID)
    }

    func allowHookOnce(name: String, argumentsJSON: String, hookIdentity: String) {
        hookOneShotKeys.insert(
            Self.hookApprovalKey(
                name: name,
                argumentsJSON: argumentsJSON,
                hookIdentity: hookIdentity
            )
        )
    }

    func allowHookForTask(
        name: String,
        argumentsJSON: String,
        hookIdentity: String,
        scopeID: String
    ) {
        grantStore.allowInvocationForTask(
            Self.hookApprovalKey(
                name: name,
                argumentsJSON: argumentsJSON,
                hookIdentity: hookIdentity
            ),
            scopeID: scopeID
        )
    }

    func allowHookLongTerm(
        name: String,
        argumentsJSON: String,
        hookIdentity: String,
        label: String
    ) {
        grantStore.allowInvocationLongTerm(
            Self.hookApprovalKey(
                name: name,
                argumentsJSON: argumentsJSON,
                hookIdentity: hookIdentity
            ),
            label: label
        )
    }

    func allowThisTask(
        name: String,
        argumentsJSON: String,
        policy: PathGuard.Policy,
        scopeID: String,
        skills: [SkillRecord] = [],
        mcpTools: [MCPToolInfo] = []
    ) {
        guard let requirement = ToolAuthorizationPolicy.requirement(
            name: name,
            argumentsJSON: argumentsJSON,
            policy: policy,
            skills: skills,
            mcpTools: mcpTools
        ) else { return }
        grantStore.allowForTask(requirement, scopeID: scopeID)
    }

    func allowLongTerm(
        name: String,
        argumentsJSON: String,
        policy: PathGuard.Policy,
        skills: [SkillRecord] = [],
        mcpTools: [MCPToolInfo] = []
    ) {
        guard let requirement = ToolAuthorizationPolicy.requirement(
            name: name,
            argumentsJSON: argumentsJSON,
            policy: policy,
            skills: skills,
            mcpTools: mcpTools
        ) else { return }
        grantStore.allowLongTerm(requirement)
    }

    func reset() {
        capabilityOneShotKeys.removeAll()
        hookOneShotKeys.removeAll()
    }

    /// SHA-256 of tool name + canonical JSON so approval is exact without storing secrets.
    nonisolated static func combinationKey(name: String, argumentsJSON: String) -> String {
        let payload = name + "\n" + normalizeJSON(argumentsJSON)
        return SHA256.hash(data: Data(payload.utf8)).hexString
    }

    nonisolated static func hookApprovalKey(
        name: String,
        argumentsJSON: String,
        hookIdentity: String
    ) -> String {
        let invocationKey = combinationKey(name: name, argumentsJSON: argumentsJSON)
        return SHA256.hash(data: Data("\(hookIdentity)\n\(invocationKey)".utf8)).hexString
    }

    nonisolated static func normalizeJSON(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              JSONSerialization.isValidJSONObject(object),
              let normalized = try? JSONSerialization.data(
                withJSONObject: object,
                options: [.sortedKeys]
              ),
              let text = String(data: normalized, encoding: .utf8)
        else { return trimmed }
        return text
    }

    nonisolated private static func capabilityKey(
        name: String,
        argumentsJSON: String,
        requirement: ToolAuthorizationRequirement
    ) -> String {
        combinationKey(name: name, argumentsJSON: argumentsJSON)
            + "\n"
            + requirement.stableKey
    }
}

enum SessionToolApprovalScope: Equatable, Sendable {
    /// Run this invocation only; the next matching call pauses again.
    case once
    /// Remember this exact tool + arguments for the rest of the task.
    case task
    /// Remember this resource grant until the user revokes it in Settings.
    case always
}

nonisolated private let sha256HexDigits: [Character] = Array("0123456789abcdef")

private extension SHA256.Digest {
    nonisolated var hexString: String {
        var hex = ""
        hex.reserveCapacity(64)
        for byte in self {
            hex.append(sha256HexDigits[Int(byte >> 4)])
            hex.append(sha256HexDigits[Int(byte & 0x0F)])
        }
        return hex
    }
}
