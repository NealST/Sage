//
//  approvals.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/approvals.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Orchestrator-stage approval types. `from(step:)` classifies live HUD
//  kinds (exec / stdin / patch / MCP / network / permissions).
//  `ApprovalStore` is the session cache `SessionToolAllowlist` writes on
//  "this task" / long-term grants so HUD and sandbox escalate share one
//  decision. Cards stay on HUD.
//

import Foundation

enum ReviewDecision: Sendable, Equatable {
    case approved
    case approvedForSession
    case denied(reason: String)
    case abort
}

struct ApprovalContext: Sendable, Equatable {
    var callID: String
    var toolName: String
    var approvalReason: String?
    var retryReason: String?
}

enum ApprovalAction: Sendable, Equatable {
    case execCommand(
        id: String,
        command: String,
        cwd: URL,
        permissionBits: SandboxPermissionBits
    )
    case writeStdin(
        id: String,
        processID: Int,
        input: String,
        cwd: URL
    )
    case applyPatch(
        id: String,
        cwd: URL,
        files: [URL],
        patch: String
    )
    case mcpToolCall(
        id: String,
        server: String,
        toolName: String,
        argumentsJSON: String
    )
    case networkAccess(
        id: String,
        host: String,
        target: String? = nil,
        port: UInt16? = nil
    )
    case requestPermissions(
        id: String,
        reason: String?,
        permissionsJSON: String
    )

    var cacheKey: String {
        switch self {
        case .execCommand(_, let command, let cwd, let bits):
            return [
                "exec",
                command,
                cwd.standardizedFileURL.path,
                String(bits.rawValue),
            ].joined(separator: "\n")

        case .writeStdin(_, let processID, let input, let cwd):
            return [
                "write_stdin",
                String(processID),
                input,
                cwd.standardizedFileURL.path,
            ].joined(separator: "\n")

        case .applyPatch(_, let cwd, let files, _):
            let paths = files
                .map { $0.standardizedFileURL.path }
                .sorted()
                .joined(separator: ",")
            return ["apply_patch", cwd.standardizedFileURL.path, paths].joined(separator: "\n")

        case .mcpToolCall(_, let server, let toolName, let argumentsJSON):
            return ["mcp", server, toolName, argumentsJSON].joined(separator: "\n")

        case .networkAccess(_, let host, let target, let port):
            return [
                "network",
                host,
                target ?? "",
                port.map(String.init) ?? "",
            ].joined(separator: "\n")

        case .requestPermissions(_, let reason, let permissionsJSON):
            return ["request_permissions", reason ?? "", permissionsJSON].joined(separator: "\n")
        }
    }

    /// Classify a HUD step the way Codex `ApprovalAction` kinds do.
    static func from(step: AgentStep, cwd: URL) -> ApprovalAction {
        switch step.toolName {
        case "apply_patch":
            let patch = (try? ApplyPatchHandler.extractPatch(from: step.argumentsJSON))
                ?? step.argumentsJSON
            return .applyPatch(
                id: step.toolCallID,
                cwd: cwd,
                files: ApplyPatchHandler.hunkPaths(in: patch, cwd: cwd),
                patch: patch
            )

        case "request_permissions":
            return .requestPermissions(
                id: step.toolCallID,
                reason: jsonString(step.argumentsJSON, key: "reason"),
                permissionsJSON: step.argumentsJSON
            )

        case "write_stdin":
            return .writeStdin(
                id: step.toolCallID,
                processID: jsonInt(step.argumentsJSON, key: "session_id")
                    ?? jsonInt(step.argumentsJSON, key: "process_id")
                    ?? 0,
                input: jsonString(step.argumentsJSON, key: "chars")
                    ?? jsonString(step.argumentsJSON, key: "input")
                    ?? step.argumentsJSON,
                cwd: cwd
            )

        case "network_access":
            let port = jsonInt(step.argumentsJSON, key: "port").flatMap { UInt16(exactly: $0) }
            return .networkAccess(
                id: step.toolCallID,
                host: jsonString(step.argumentsJSON, key: "host") ?? "",
                target: jsonString(step.argumentsJSON, key: "target"),
                port: port
            )

        default:
            if let server = MCPToolGroupTool.serverName(fromQualifiedTool: step.toolName)
                ?? MCPToolGroupTool.serverName(fromGroupTool: step.toolName)
            {
                return .mcpToolCall(
                    id: step.toolCallID,
                    server: server,
                    toolName: mcpShortName(step.toolName),
                    argumentsJSON: step.argumentsJSON
                )
            }
            return .execCommand(
                id: step.toolCallID,
                command: "\(step.toolName) \(step.argumentsJSON)",
                cwd: cwd,
                permissionBits: []
            )
        }
    }

    private static func mcpShortName(_ qualified: String) -> String {
        let parts = qualified.split(separator: "__", maxSplits: 2, omittingEmptySubsequences: false)
        if qualified.hasPrefix("mcp__"), parts.count >= 3 {
            return String(parts[2])
        }
        return qualified
    }

    private static func jsonObject(_ raw: String) -> [String: Any] {
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return object
    }

    private static func jsonString(_ raw: String, key: String) -> String? {
        guard let value = jsonObject(raw)[key] else { return nil }
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    private static func jsonInt(_ raw: String, key: String) -> Int? {
        guard let value = jsonObject(raw)[key] else { return nil }
        if let int = value as? Int { return int }
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) }
        return nil
    }
}

/// Serialized-key cache matching Codex `ApprovalStore`.
@MainActor
final class ApprovalStore {
    private var map: [String: ReviewDecision] = [:]

    func get(_ key: String) -> ReviewDecision? {
        map[key]
    }

    func put(_ key: String, _ value: ReviewDecision) {
        map[key] = value
    }

    func reset() {
        map.removeAll()
    }

    /// Same identity `SessionToolAllowlist` uses for a tool + args grant.
    static func sessionCacheKey(name: String, argumentsJSON: String) -> String {
        "sage\n" + SessionToolAllowlist.combinationKey(name: name, argumentsJSON: argumentsJSON)
    }
}

@MainActor
func withCachedApproval(
    store: ApprovalStore,
    keys: [String],
    fetch: () async throws -> ReviewDecision
) async throws -> ReviewDecision {
    if !keys.isEmpty,
       keys.contains(where: { store.get($0) == .approvedForSession }) {
        return .approvedForSession
    }

    let decision = try await fetch()
    if decision == .approvedForSession {
        for key in keys {
            store.put(key, decision)
        }
    }
    return decision
}

protocol ApprovalRequesting: Sendable {
    func requestApproval(
        action: ApprovalAction,
        context: ApprovalContext
    ) async throws -> ReviewDecision
}

enum SandboxEscalation {
    static let titlePrefix = "Sandbox denied this command."

    static func title(reason: String, original: String) -> String {
        "\(titlePrefix) \(reason)\n\(original)"
    }

    static func isEscalation(_ title: String) -> Bool {
        title.hasPrefix(titlePrefix)
    }
}

/// Turns Sage's existing capability evidence into an orchestrator decision.
struct InvocationApprover: ApprovalRequesting {
    var authorization: ToolAuthorizationRequirement?
    var evidence: ToolInvocationAuthorizationEvidence?

    func requestApproval(
        action _: ApprovalAction,
        context: ApprovalContext
    ) async throws -> ReviewDecision {
        if let retryReason = context.retryReason {
            throw HarnessToolError.needsEscalationApproval(reason: retryReason)
        }
        guard let authorization else {
            return .approved
        }
        guard evidence?.requirementKey == authorization.stableKey else {
            throw HarnessToolError.rejected("This tool call requires authorization.")
        }
        return .approved
    }
}
