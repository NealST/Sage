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
    private var oneShotKeys: Set<String> = []
    private var keys: Set<String> = []
    private var toolNames: Set<String> = []

    /// Shell and MCP can still change the Mac after the work plan is approved.
    nonisolated static func needsGate(forToolNamed name: String) -> Bool {
        name == "run_shell_command" || name.hasPrefix("mcp__")
    }

    func contains(name: String, argumentsJSON: String) -> Bool {
        guard Self.needsGate(forToolNamed: name) else { return true }
        if toolNames.contains(name) { return true }
        let key = Self.combinationKey(name: name, argumentsJSON: argumentsJSON)
        return keys.contains(key) || oneShotKeys.contains(key)
    }

    /// Returns approval and consumes an Allow Once grant exactly once.
    func consumeApproval(name: String, argumentsJSON: String) -> Bool {
        if toolNames.contains(name) { return true }
        let key = Self.combinationKey(name: name, argumentsJSON: argumentsJSON)
        if keys.contains(key) { return true }
        return oneShotKeys.remove(key) != nil
    }

    func allowOnce(name: String, argumentsJSON: String) {
        oneShotKeys.insert(Self.combinationKey(name: name, argumentsJSON: argumentsJSON))
    }

    func allowThisSession(name: String, argumentsJSON: String) {
        keys.insert(Self.combinationKey(name: name, argumentsJSON: argumentsJSON))
    }

    func allowToolThisSession(named name: String) {
        toolNames.insert(name)
    }

    func reset() {
        oneShotKeys.removeAll()
        keys.removeAll()
        toolNames.removeAll()
    }

    /// SHA-256 of tool name + canonical JSON so approval is exact without storing secrets.
    nonisolated static func combinationKey(name: String, argumentsJSON: String) -> String {
        let payload = name + "\n" + normalizeJSON(argumentsJSON)
        return SHA256.hash(data: Data(payload.utf8)).hexString
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
}

enum SessionToolApprovalScope: Equatable, Sendable {
    /// Run this invocation only; the next matching call pauses again.
    case once
    /// Remember this exact tool + arguments for the rest of the task.
    case session
    /// Remember this tool name with any arguments for the rest of the task.
    case tool
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
